// The email package contains functions for directly sending emails.
//
// These functions can be used for directly sending emails to given email
// addresses. This is used for transactional emails, for example OTP requests.
package email

import (
	"bytes"
	"crypto/tls"
	"fmt"
	"html/template"
	"mime/quotedprintable"
	"net"
	"net/smtp"
	"path"
	"slices"
	"strings"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/viper"
)

var knownInvalidEmailErrors = []string{
	"Invalid RCPT TO address provided",
	"Invalid domain name",
}

// NormalizeEmail returns a canonical form for case-insensitive email lookup and hashing.
func NormalizeEmail(email string) string {
	return strings.ToLower(strings.TrimSpace(email))
}

// https://datatracker.ietf.org/doc/html/rfc5322#section-2.1.1
const base64LineLength = 900 // standard MIME line length for base64 content

// sanitizeHeaderValue removes CR/LF and other control characters from header values
// to prevent header injection and ensures values are single-line.
func sanitizeHeaderValue(s string) string {
	if s == "" {
		return s
	}
	var b strings.Builder
	b.Grow(len(s))
	for _, r := range s {
		// Disallow CR and LF entirely in header values
		if r == '\r' || r == '\n' {
			continue
		}
		// Strip other ASCII control chars except tab
		if r < 0x20 && r != '\t' {
			continue
		}
		b.WriteRune(r)
	}
	return strings.TrimSpace(b.String())
}

// containsCRLF checks for raw CR/LF which must not appear in addresses
func containsCRLF(s string) bool {
	return strings.ContainsRune(s, '\r') || strings.ContainsRune(s, '\n')
}

// wrapToMaxLineLength inserts LF breaks into long base64 blobs to respect SMTP limits.
func wrapToMaxLineLength(s string, maxLen int) string {
	if maxLen <= 0 {
		return s
	}
	// Remove existing line breaks so we can re-wrap deterministically.
	clean := strings.ReplaceAll(strings.ReplaceAll(s, "\r", ""), "\n", "")
	if len(clean) <= maxLen {
		return clean
	}

	var b strings.Builder
	// Grow buffer to avoid re-allocations; add extra space for newline characters.
	b.Grow(len(clean) + len(clean)/maxLen)
	for i := 0; i < len(clean); i += maxLen {
		end := min(i+maxLen, len(clean))
		b.WriteString(clean[i:end])
		if end < len(clean) {
			b.WriteByte('\n')
		}
	}
	return b.String()
}

func buildHTMLMIMEPart(htmlBody string) (string, error) {
	var encodedBody bytes.Buffer
	writer := quotedprintable.NewWriter(&encodedBody)
	if _, err := writer.Write([]byte(htmlBody)); err != nil {
		return "", err
	}
	if err := writer.Close(); err != nil {
		return "", err
	}

	return "Content-Type: text/html; charset=utf-8\n" +
		"Content-Transfer-Encoding: quoted-printable\n\n" +
		encodedBody.String() + "\n", nil
}

// Send sends an email
func Send(toEmails []string, fromName string, fromEmail string, subject string, htmlBody string, inlineImages []map[string]interface{}) error {
	if len(toEmails) == 0 {
		return ente.ErrBadRequest
	}
	if viper.GetString("smtp.host") == "" {
		log.Infof("Skipping sending email to %s: %s", toEmails[0], subject)
		return nil
	}
	return sendViaSMTP(toEmails, fromName, fromEmail, subject, htmlBody, inlineImages)
}

func sendViaSMTP(toEmails []string, fromName string, fromEmail string, subject string, htmlBody string, inlineImages []map[string]interface{}) error {
	smtpServer := viper.GetString("smtp.host")
	smtpPort := viper.GetString("smtp.port")
	smtpUsername := viper.GetString("smtp.username")
	smtpPassword := viper.GetString("smtp.password")
	smtpEmail := viper.GetString("smtp.email")
	smtpSenderName := viper.GetString("smtp.sender-name")
	smtpEncryption := viper.GetString("smtp.encryption")

	var emailMessage string
	var auth smtp.Auth = nil
	if smtpUsername != "" && smtpPassword != "" {
		auth = smtp.PlainAuth("", smtpUsername, smtpPassword, smtpServer)
	}

	// Validate that no envelope addresses contain CR/LF
	if containsCRLF(fromEmail) {
		return stacktrace.Propagate(ente.ErrBadRequest, "invalid from email")
	}
	if slices.ContainsFunc(toEmails, containsCRLF) {
		return stacktrace.Propagate(ente.ErrBadRequest, "invalid recipient email")
	}

	// If a sender email is provided use it instead of the fromEmail.
	if smtpEmail != "" {
		fromEmail = smtpEmail
	}
	// If a sender name is provided use it instead of the fromName.
	if smtpSenderName != "" {
		fromName = smtpSenderName
	}

	// Sanitize header fields to prevent header injection
	cleanFromName := sanitizeHeaderValue(fromName)
	cleanFromEmail := sanitizeHeaderValue(fromEmail)
	cleanSubject := sanitizeHeaderValue(subject)

	// Construct 'emailAddresses' with comma-separated sanitized email addresses for header
	var emailAddresses string
	for i, addr := range toEmails {
		if i != 0 {
			emailAddresses += ","
		}
		emailAddresses += sanitizeHeaderValue(addr)
	}

	header := "Date: " + time.Now().Format(time.RFC1123Z) + "\n" +
		"From: " + cleanFromName + " <" + cleanFromEmail + ">\n" +
		"To: " + emailAddresses + "\n" +
		"Subject: " + cleanSubject + "\n" +
		"MIME-Version: 1.0\n" +
		"Content-Type: multipart/related; boundary=boundary\n\n" +
		"--boundary\n"
	htmlContent, err := buildHTMLMIMEPart(htmlBody)
	if err != nil {
		return stacktrace.Propagate(err, "failed to encode html body")
	}

	emailMessage = header + htmlContent

	if inlineImages == nil {
		emailMessage += "--boundary--"
	} else {
		for _, inlineImage := range inlineImages {

			emailMessage += "--boundary\n"
			var mimeType = sanitizeHeaderValue(inlineImage["mime_type"].(string))
			var contentID = sanitizeHeaderValue(inlineImage["cid"].(string))
			var imgBase64Str = inlineImage["content"].(string)
			var wrappedImgBase64Str = wrapToMaxLineLength(imgBase64Str, base64LineLength)

			var image = "Content-Type: " + mimeType + "\n" +
				"Content-Transfer-Encoding: base64\n" +
				"Content-ID: <" + contentID + ">\n" +
				"Content-Disposition: inline\n\n" + wrappedImgBase64Str + "\n"

			emailMessage += image
		}
		emailMessage += "--boundary--"
	}

	// Send the email to each recipient
	for _, toEmail := range toEmails {
		err := sendMailWithEncryption(smtpServer, smtpPort, auth, fromEmail, []string{toEmail}, []byte(emailMessage), smtpEncryption)
		if err != nil {
			errMsg := err.Error()
			for i := range knownInvalidEmailErrors {
				if strings.Contains(errMsg, knownInvalidEmailErrors[i]) {
					return stacktrace.Propagate(ente.NewBadRequestWithMessage(fmt.Sprintf("Invalid email %s", toEmail)), "%v", err)
				}
			}
			return stacktrace.Propagate(err, "")
		}
	}

	return nil
}

// sendMailWithEncryption sends an email with the specified encryption type
// encryption can be one of:
// - "tls" or "ssl": Uses TLS/SSL encryption for the entire connection
// - "" (empty string) or any other value: No encryption
func sendMailWithEncryption(host, port string, auth smtp.Auth, from string, to []string, msg []byte, encryption string) error {
	addr := net.JoinHostPort(host, port)

	switch strings.ToLower(encryption) {
	case "tls", "ssl":
		// For TLS/SSL, establish a secure connection directly
		tlsConfig := &tls.Config{
			ServerName: host,
			MinVersion: tls.VersionTLS12,
		}
		conn, err := tls.Dial("tcp", addr, tlsConfig)
		if err != nil {
			return stacktrace.Propagate(err, "failed to establish TLS connection")
		}
		defer conn.Close()

		client, err := smtp.NewClient(conn, host)
		if err != nil {
			return stacktrace.Propagate(err, "failed to create SMTP client over TLS")
		}
		defer client.Close()

		return sendWithClient(client, auth, from, to, msg)

	default:
		// No encryption, use standard SendMail
		return smtp.SendMail(addr, auth, from, to, msg)
	}
}

// sendWithClient sends an email using an established SMTP client
func sendWithClient(client *smtp.Client, auth smtp.Auth, from string, to []string, msg []byte) error {
	if auth != nil {
		if err := client.Auth(auth); err != nil {
			return stacktrace.Propagate(err, "authentication failed")
		}
	}

	if err := client.Mail(from); err != nil {
		return stacktrace.Propagate(err, "failed to set sender")
	}

	for _, addr := range to {
		if err := client.Rcpt(addr); err != nil {
			return stacktrace.Propagate(err, "failed to add recipient")
		}
	}

	w, err := client.Data()
	if err != nil {
		return stacktrace.Propagate(err, "failed to create message writer")
	}

	_, err = w.Write(msg)
	if err != nil {
		return stacktrace.Propagate(err, "failed to write message")
	}

	err = w.Close()
	if err != nil {
		return stacktrace.Propagate(err, "failed to close message writer")
	}

	err = client.Quit()
	return stacktrace.Propagate(err, "")
}

func SendTemplatedEmail(to []string, fromName string, fromEmail string, subject string, templateName string, templateData map[string]interface{}, inlineImages []map[string]interface{}) error {
	body, err := getMailBody(templateName, templateData)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}

	return Send(to, fromName, fromEmail, subject, body, inlineImages)
}

func SendTemplatedEmailV2(to []string, fromName string, fromEmail string, subject string, baseTemplate, templateName string, templateData map[string]interface{}, inlineImages []map[string]interface{}) error {
	body, err := getMailBodyWithBase(baseTemplate, templateName, templateData)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}

	return Send(to, fromName, fromEmail, subject, body, inlineImages)
}

func GetMaskedEmail(email string) string {
	at := strings.LastIndex(email, "@")
	if at >= 0 {
		username, domain := email[:at], email[at+1:]
		maskedUsername := ""
		for i := 0; i < len(username); i++ {
			maskedUsername += "*"
		}
		return maskedUsername + "@" + domain
	} else {
		// Should ideally never happen, there should always be an @ symbol
		return "[invalid_email]"
	}
}

// GetMaskedEmailForPublic masks an email for public display.
// Format: first 2 chars of username + masked remainder + @ + first char of domain + masked middle + last char of domain
func GetMaskedEmailForPublic(email string) string {
	email = strings.TrimSpace(email)
	at := strings.LastIndex(email, "@")
	if at <= 0 || at == len(email)-1 {
		return "[invalid_email]"
	}
	username := email[:at]
	domain := email[at+1:]

	maskedUsername := maskForPublicUsername(username)
	maskedDomain := maskForPublicDomain(domain)

	return maskedUsername + "@" + maskedDomain
}

// maskForPublicUsername masks a username keeping the first 2 runes visible.
// Remaining runes are replaced with asterisks.
func maskForPublicUsername(s string) string {
	runes := []rune(s)
	if len(runes) <= 2 {
		return s
	}
	return string(runes[:2]) + strings.Repeat("*", len(runes)-2)
}

// maskForPublicDomain masks a domain showing first and last rune.
// Middle runes are replaced with asterisks.
func maskForPublicDomain(domain string) string {
	runes := []rune(domain)
	if len(runes) <= 2 {
		return domain
	}
	return string(runes[0]) + strings.Repeat("*", len(runes)-2) + string(runes[len(runes)-1])
}

// GetMaskedEmailWithHint masks both the username and non-TLD domain segments while keeping helpful hints.
func GetMaskedEmailWithHint(email string) string {
	email = strings.TrimSpace(email)
	at := strings.LastIndex(email, "@")
	if at <= 0 || at == len(email)-1 {
		return "[invalid_email]"
	}
	local := email[:at]
	domain := email[at+1:]

	maskedLocal := maskEmailSegment(local)
	if domain == "" {
		return maskedLocal + "@[invalid_domain]"
	}

	domainParts := strings.Split(domain, ".")
	if len(domainParts) == 1 {
		return fmt.Sprintf("%s@%s", maskedLocal, maskEmailSegment(domainParts[0]))
	}

	tld := domainParts[len(domainParts)-1]
	mainParts := domainParts[:len(domainParts)-1]
	for i, part := range mainParts {
		mainParts[i] = maskEmailSegment(part)
	}
	return fmt.Sprintf("%s@%s.%s", maskedLocal, strings.Join(mainParts, "."), tld)
}

func maskEmailSegment(segment string) string {
	segment = strings.TrimSpace(segment)
	if segment == "" {
		return "*"
	}
	if len(segment) == 1 {
		return segment + "*"
	}
	if len(segment) == 2 {
		return segment[:1] + "*"
	}
	return segment[:1] + strings.Repeat("*", len(segment)-2) + segment[len(segment)-1:]
}

// getMailBody generates the mail html body from provided template and data
func getMailBody(templateName string, templateData map[string]interface{}) (string, error) {
	htmlbody := new(bytes.Buffer)
	t := template.Must(template.New(templateName).ParseFiles("mail-templates/" + templateName))
	err := t.Execute(htmlbody, templateData)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	return htmlbody.String(), nil
}

// getMailBody generates the mail HTML body from the provided template and data, supporting inheritance
func getMailBodyWithBase(baseTemplateName, templateName string, templateData map[string]interface{}) (string, error) {
	htmlBody := new(bytes.Buffer)

	// Define paths for the base template and the specific template
	baseTemplate := "mail-templates/" + baseTemplateName
	specificTemplate := "mail-templates/" + templateName

	parts := strings.Split(baseTemplate, "/")
	lastPart := parts[len(parts)-1]
	baseTemplateID := strings.TrimSuffix(lastPart, path.Ext(lastPart))

	// Parse the base and specific templates together
	t, err := template.ParseFiles(baseTemplate, specificTemplate)
	if err != nil {
		return "", stacktrace.Propagate(err, "failed to parse templates")
	}

	// Execute the base template with the provided data
	err = t.ExecuteTemplate(htmlBody, baseTemplateID, templateData)
	if err != nil {
		return "", stacktrace.Propagate(err, "failed to execute template")
	}

	return htmlBody.String(), nil
}
