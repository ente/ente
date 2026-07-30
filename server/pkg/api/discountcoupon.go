package api

import (
	"net/http"

	"github.com/ente/museum/pkg/controller/discountcoupon"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/gin-gonic/gin"
)

type DiscountCouponHandler struct {
	Controller *discountcoupon.Controller
}

func (h *DiscountCouponHandler) ClaimCoupon(c *gin.Context) {
	var req discountcoupon.ClaimCouponRequest
	if err := handler.BindJSON(c, &req); err != nil {
		handler.Error(c, err)
		return
	}
	err := h.Controller.ClaimCoupon(c, req)
	if err != nil {
		handler.Error(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "If you are paid subscriber, you should shortly get an email."})
}

func (h *DiscountCouponHandler) AddCoupons(c *gin.Context) {
	var req discountcoupon.AddCouponsRequest
	if err := handler.BindJSON(c, &req); err != nil {
		handler.Error(c, err)
		return
	}

	err := h.Controller.AddCoupons(c, req)
	if err != nil {
		handler.Error(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Coupons added successfully"})
}
