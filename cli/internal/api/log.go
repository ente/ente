package api

import (
	"fmt"
	"strings"

	"github.com/fatih/color"
	"github.com/go-resty/resty/v2"
)

func logRequest(req *resty.Request) {
	fmt.Println(color.GreenString("Request:"))
	fmt.Printf("%s %s\n", color.CyanString(req.Method), color.YellowString(req.URL))
	fmt.Println(color.GreenString("Headers:"))
	for k, v := range req.Header {
		redacted := false
		for _, rh := range RedactedHeaders {
			if strings.EqualFold(strings.ToLower(k), strings.ToLower(rh)) {
				redacted = true
				break
			}
		}
		if redacted {
			fmt.Printf("%s: %s\n", color.CyanString(k), color.RedString("REDACTED"))
		} else {
			if len(v) == 1 {
				fmt.Printf("%s: %s\n", color.CyanString(k), color.YellowString(v[0]))
			} else {
				fmt.Printf("%s: %s\n", color.CyanString(k), color.YellowString(strings.Join(v, ",")))
			}
		}
	}
	if len(req.QueryParam) > 0 {
		fmt.Println(color.GreenString("Query Params:"))
		for k, v := range req.QueryParam {
			if k == TokenQuery {
				v = []string{"REDACTED"}
			}
			fmt.Printf("%s: %s\n", color.CyanString(k), color.YellowString(strings.Join(v, ",")))
		}
	}
}

func logResponse(resp *resty.Response) {
	fmt.Println(color.GreenString("Response:"))
	if resp.StatusCode() < 200 || resp.StatusCode() >= 300 {
		fmt.Printf("%s %s\n", color.CyanString(resp.Proto()), color.RedString(resp.Status()))
	} else {
		fmt.Printf("%s %s\n", color.CyanString(resp.Proto()), color.YellowString(resp.Status()))
	}
	fmt.Printf("Time Duration: %s\n", resp.Time())
	fmt.Println(color.GreenString("Headers:"))
	for k, v := range resp.Header() {
		redacted := false
		for _, rh := range RedactedHeaders {
			if strings.EqualFold(strings.ToLower(k), strings.ToLower(rh)) {
				redacted = true
				break
			}
		}
		if redacted {
			fmt.Printf("%s: %s\n", color.CyanString(k), color.RedString("REDACTED"))
		} else {
			fmt.Printf("%s: %s\n", color.CyanString(k), color.YellowString(strings.Join(v, ",")))
		}
	}
}
