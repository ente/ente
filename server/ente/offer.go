package ente

type BlackFridayOffer struct {
	ID            string `json:"id"`
	Storage       int64  `json:"storage"`
	Price         string `json:"price"`
	OldPrice      string `json:"oldPrice"`
	PeriodInYears string `json:"periodInYears"`
	PaymentLink   string `json:"paymentLink"`
}

type BlackFridayOfferPerCountry map[string][]BlackFridayOffer

const (
	BF2024EmailTemplate = "bf_2024.html"
	BF2024EmailSubject  = "Black Friday deal confirmation"
)
