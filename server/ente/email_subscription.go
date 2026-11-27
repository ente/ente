package ente

type EmailType string

const ProductMailsEmailType EmailType = "product_mails"

func (t EmailType) Label() string {
	switch t {
	case ProductMailsEmailType:
		return "Product Mails"
	default:
		return ""
	}
}
