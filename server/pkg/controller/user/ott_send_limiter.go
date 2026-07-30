package user

import (
	"sync"
	"time"
)

const (
	ottSendAttackWindow        = 5 * time.Minute
	ottSendIPCooldown          = 5 * time.Minute
	ottSendElevatedThreshold   = 50
	ottSendSevereThreshold     = 200
	ottSendSevereBlockDuration = 10 * time.Minute

	ottSendElevatedAlert = "OTT send volume reached 50/5m; limiting each IP to one request per 5m"
	ottSendSevereAlert   = "OTT send volume reached 200/5m; blocking all OTT sends for 10m"
)

type ottSendLimiterDecision struct {
	allowed bool
	alert   string
}

type OTTSendLimiter struct {
	mu sync.Mutex

	now func() time.Time

	attempts      []time.Time
	ipNextAllowed map[string]time.Time
	blockedUntil  time.Time
}

func NewOTTSendLimiter() *OTTSendLimiter {
	return newOTTSendLimiter(time.Now)
}

func newOTTSendLimiter(now func() time.Time) *OTTSendLimiter {
	return &OTTSendLimiter{
		now:           now,
		ipNextAllowed: make(map[string]time.Time),
	}
}

func (l *OTTSendLimiter) IsGloballyBlocked() bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	return l.isGloballyBlockedAt(l.now())
}

func (l *OTTSendLimiter) Allow(ip string) ottSendLimiterDecision {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := l.now()
	l.prune(now)
	if l.isGloballyBlockedAt(now) {
		return ottSendLimiterDecision{}
	}

	l.attempts = append(l.attempts, now)
	if len(l.attempts) >= ottSendSevereThreshold {
		l.blockedUntil = now.Add(ottSendSevereBlockDuration)
		return ottSendLimiterDecision{alert: ottSendSevereAlert}
	}

	decision := ottSendLimiterDecision{allowed: true}
	if len(l.attempts) >= ottSendElevatedThreshold {
		if len(l.attempts) == ottSendElevatedThreshold {
			decision.alert = ottSendElevatedAlert
		}
		if nextAllowed, ok := l.ipNextAllowed[ip]; ok && now.Before(nextAllowed) {
			decision.allowed = false
			return decision
		}
	}

	l.ipNextAllowed[ip] = now.Add(ottSendIPCooldown)
	return decision
}

func (l *OTTSendLimiter) isGloballyBlockedAt(now time.Time) bool {
	if now.Before(l.blockedUntil) {
		return true
	}
	if !l.blockedUntil.IsZero() {
		l.blockedUntil = time.Time{}
	}
	return false
}

func (l *OTTSendLimiter) prune(now time.Time) {
	cutoff := now.Add(-ottSendAttackWindow)
	firstRecent := 0
	for firstRecent < len(l.attempts) && !l.attempts[firstRecent].After(cutoff) {
		firstRecent++
	}
	if firstRecent > 0 {
		l.attempts = l.attempts[firstRecent:]
	}

	for ip, nextAllowed := range l.ipNextAllowed {
		if !now.Before(nextAllowed) {
			delete(l.ipNextAllowed, ip)
		}
	}
}
