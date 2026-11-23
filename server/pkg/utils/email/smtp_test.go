package email

import (
	"net"
	"net/smtp"
	"net/textproto"
	"strings"
	"sync"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// fakeSMTPServer offers STARTTLS but rejects it, and records the commands it receives.
type fakeSMTPServer struct {
	listener net.Listener
	mu       sync.Mutex
	commands []string
	data     string
}

func newFakeSMTPServer(t *testing.T) *fakeSMTPServer {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	t.Cleanup(func() { listener.Close() })

	s := &fakeSMTPServer{listener: listener}
	go s.serve()
	return s
}

func (s *fakeSMTPServer) hostPort(t *testing.T) (string, string) {
	t.Helper()
	host, port, err := net.SplitHostPort(s.listener.Addr().String())
	require.NoError(t, err)
	return host, port
}

func (s *fakeSMTPServer) serve() {
	conn, err := s.listener.Accept()
	if err != nil {
		return
	}
	tp := textproto.NewConn(conn)
	defer tp.Close()

	_ = tp.PrintfLine("220 fake ESMTP")
	for {
		line, err := tp.ReadLine()
		if err != nil {
			return
		}
		verb, _, _ := strings.Cut(line, " ")
		verb = strings.ToUpper(verb)

		s.mu.Lock()
		s.commands = append(s.commands, verb)
		s.mu.Unlock()

		switch verb {
		case "EHLO":
			_ = tp.PrintfLine("250-fake")
			_ = tp.PrintfLine("250 STARTTLS")
		case "STARTTLS":
			_ = tp.PrintfLine("454 TLS not available")
		case "DATA":
			_ = tp.PrintfLine("354 go ahead")
			lines, err := tp.ReadDotLines()
			if err != nil {
				return
			}
			s.mu.Lock()
			s.data = strings.Join(lines, "\n")
			s.mu.Unlock()
			_ = tp.PrintfLine("250 OK")
		case "QUIT":
			_ = tp.PrintfLine("221 bye")
			return
		default:
			_ = tp.PrintfLine("250 OK")
		}
	}
}

func (s *fakeSMTPServer) receivedCommands() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]string(nil), s.commands...)
}

func (s *fakeSMTPServer) receivedData() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.data
}

func TestSendMailWithEncryptionNoneSkipsStartTLS(t *testing.T) {
	server := newFakeSMTPServer(t)
	host, port := server.hostPort(t)

	err := sendMailWithEncryption(host, port, nil, "from@example.com", []string{"to@example.com"},
		[]byte("Subject: test\r\n\r\nhello\r\n"), "none")
	require.NoError(t, err)

	assert.NotContains(t, server.receivedCommands(), "STARTTLS")
	assert.Equal(t, []string{"EHLO", "MAIL", "RCPT", "DATA", "QUIT"}, server.receivedCommands())
	assert.Contains(t, server.receivedData(), "hello")
}

func TestSendMailWithEncryptionNoneRejectsAuth(t *testing.T) {
	server := newFakeSMTPServer(t)
	host, port := server.hostPort(t)
	auth := smtp.PlainAuth("", "user", "pass", host)

	err := sendMailWithEncryption(host, port, auth, "from@example.com", []string{"to@example.com"},
		[]byte("Subject: test\r\n\r\nhello\r\n"), "none")
	assert.ErrorContains(t, err, "smtp.encryption none cannot be used with smtp.username and smtp.password")
	assert.Empty(t, server.receivedCommands())
}

func TestSendMailWithEncryptionDefaultUsesStartTLS(t *testing.T) {
	server := newFakeSMTPServer(t)
	host, port := server.hostPort(t)

	err := sendMailWithEncryption(host, port, nil, "from@example.com", []string{"to@example.com"},
		[]byte("Subject: test\r\n\r\nhello\r\n"), "")
	require.Error(t, err)

	assert.Equal(t, []string{"EHLO", "STARTTLS"}, server.receivedCommands())
}
