package discord

import (
	"fmt"
	"sync"
	"time"

	"github.com/bwmarrin/discordgo"
	"github.com/ente/museum/pkg/repo"
	t "github.com/ente/museum/pkg/utils/time"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/viper"
)

// DiscordController is an devops aid. If Discord credentials are configured,
// then it will send notifications to Discord channels on specified events.
type DiscordController struct {
	MonaLisa    *discordgo.Session
	ChaChing    *discordgo.Session
	HostName    string
	Environment string
	UserRepo    *repo.UserRepository
	lastSent    map[string]time.Time
	mu          sync.Mutex
}

func NewDiscordController(userRepo *repo.UserRepository, hostName string, environment string) *DiscordController {
	return &DiscordController{
		MonaLisa:    createBot("Mona Lisa", "discord.bot.mona-lisa.token"),
		ChaChing:    createBot("Cha Ching", "discord.bot.cha-ching.token"),
		HostName:    hostName,
		Environment: environment,
		UserRepo:    userRepo,
		lastSent:    make(map[string]time.Time),
	}
}

func createBot(name string, tokenConfigKey string) *discordgo.Session {
	silent := viper.GetBool("internal.silent")
	if silent {
		return nil
	}

	token := viper.GetString(tokenConfigKey)
	if token == "" {
		return nil
	}

	session, err := discordgo.New("Bot " + token)
	if err != nil {
		log.Warnf("Could not create Discord bot %s: %s", name, err)
	}

	return session
}

// The actual send
func (c *DiscordController) sendMessage(bot *discordgo.Session, channel string, message string) {
	if bot == nil {
		log.Infof("Skipping sending Discord message: %s", message)
		return
	}

	_, err := bot.ChannelMessageSend(channel, message)
	if err != nil {
		log.Warnf("Could not send message {%s} to Discord channel {%s} due to error {%s}", message, channel, err)
	}
}

// Send a message related to server status or important events/errors.
func (c *DiscordController) Notify(message string) {
	c.sendMessage(c.MonaLisa, viper.GetString("discord.bot.mona-lisa.channel"), message)
}

func (c *DiscordController) NotifyThrottled(message string, window time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()

	now := time.Now()
	if lastTime, exists := c.lastSent[message]; exists && now.Sub(lastTime) < window {
		log.Infof("Skipping duplicate Discord notification: %s", message)
		return
	}
	c.lastSent[message] = now
	c.Notify(message)
}

// Send a message related to subscriptions.
func (c *DiscordController) NotifyNewSub(userID int64, paymentProvider string, amount string) {
	message := fmt.Sprintf("New subscriber via `%s`, after %s of signing up! 🫂 (%s)",
		paymentProvider, c.getTimeSinceSignUp(userID), amount)
	c.sendMessage(c.ChaChing, viper.GetString("discord.bot.cha-ching.channel"), message)
}

// Send a message related to subscriptions.
func (c *DiscordController) NotifyBlackFridayUser(userID int64, amount string) {
	message := fmt.Sprintf("BlackFriday subscription purchased after %s of signing up! 🫂 (%s)",
		c.getTimeSinceSignUp(userID), amount)
	c.sendMessage(c.ChaChing, viper.GetString("discord.bot.cha-ching.channel"), message)
}

// Convenience wrappers over the primitive notify types.
//
// By keeping them separate we later allow them to be routed easily to different
// Discord channels.

func (c *DiscordController) NotifyStartup() {
	c.Notify(c.HostName + " has taken off 🚀")
}

func (c *DiscordController) NotifyShutdown() {
	c.Notify(c.HostName + " is down ☠️")
}

func (c *DiscordController) NotifyAdminAction(message string) {
	c.Notify(message)
}

func (c *DiscordController) NotifyAccountDelete(userID int64, paymentProvider string, productID string) {
	message := fmt.Sprintf("User on %s (%s) initiated delete after using us for %s",
		paymentProvider, productID, c.getTimeSinceSignUp(userID))
	c.Notify(message)
}

func (c *DiscordController) NotifyPotentialAbuse(message string) {
	c.NotifyThrottled(fmt.Sprintf("%s: %s", c.HostName, message), time.Minute)
}

func (c *DiscordController) getTimeSinceSignUp(userID int64) string {
	timeSinceSignUp := "unknown time"
	user, err := c.UserRepo.GetUserByIDInternal(userID)
	if err != nil {
		log.Error(err)
	} else {
		since := time.Since(time.UnixMicro(user.CreationTime))
		timeSinceSignUp = t.DaysOrHoursOrMinutes(since)
	}
	return timeSinceSignUp
}
