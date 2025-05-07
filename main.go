package main

import (
	"fmt"
	"log"
	"math/rand"
	"os"
	"strings"
	"time"

	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api/v5"
)

// Kata-kata dari KBBI (contoh sederhana, bisa diperluas)
var kata = []string{
	"hore", "kenapa", "aman", "beli", "cari", "damai", "enak", "fakta",
	"ganti", "harap", "indah", "jalan", "kaya", "lama", "makan", "nama",
	"opini", "pakai", "quran", "rasa", "suka", "tanya", "untuk", "vokal",
	"warna", "xenon", "yakin", "zebra", "sakit", "sikat", "suntuk", "sumpah", "sebel", "sudah",  "foto", "izin", "karir", "karena", "kamu"
}

func generateUsername(word string) string {
	// Mengambil 2-5 huruf pertama dari kata
	wordLen := len(word)
	if wordLen <= 2 {
		// Jika kata terlalu pendek, gunakan seluruh kata
		wordLen = len(word)
	} else {
		// Mengambil antara 2-5 huruf atau seluruh kata jika lebih pendek
		maxLen := 5
		if wordLen < maxLen {
			maxLen = wordLen
		}
		wordLen = rand.Intn(maxLen-1) + 2 // Minimal 2 huruf, maksimal 5 atau seluruh kata
	}
	
	prefix := word[:wordLen]
	
	// Menambahkan 2-3 huruf random dari a-z
	randomLen := rand.Intn(2) + 2 // 2-3 huruf
	randomChars := make([]byte, randomLen)
	
	for i := 0; i < randomLen; i++ {
		randomChars[i] = byte('a' + rand.Intn(26))
	}
	
	return prefix + string(randomChars)
}

func handleCommand(update tgbotapi.Update, bot *tgbotapi.BotAPI) {
	msg := tgbotapi.NewMessage(update.Message.Chat.ID, "")
	
	switch update.Message.Command() {
	case "start":
		msg.Text = "selamat datang by @lketipu\n" +
			"gunakan perintah /generate untuk mendapatkan username baru dari KBBI.\n" +
			"Contoh hasil: @horqe (dari kata hore), @kenoa (dari kata kenapa)"
	
	case "generate":
		// Pilih kata random dari daftar kata KBBI
		randomIndex := rand.Intn(len(kata))
		selectedWord := kata[randomIndex]
		
		// Generate username
		username := generateUsername(selectedWord)
		
		msg.Text = fmt.Sprintf("Username dari kata '%s': @%s", selectedWord, username)
	
	default:
		msg.Text = "Perintah tidak dikenal. Gunakan /generate untuk membuat username baru."
	}
	
	if _, err := bot.Send(msg); err != nil {
		log.Printf("Error sending message: %v", err)
	}
}

func handleMessage(update tgbotapi.Update, bot *tgbotapi.BotAPI) {
	if update.Message == nil {
		return
	}
	
	if update.Message.IsCommand() {
		handleCommand(update, bot)
		return
	}
	
	// Untuk pesan biasa, cek apakah itu kata dari KBBI
	userWord := strings.TrimSpace(strings.ToLower(update.Message.Text))
	
	// Cek apakah kata ada dalam daftar kata KBBI
	validWord := false
	for _, word := range kata {
		if word == userWord {
			validWord = true
			break
		}
	}
	
	msg := tgbotapi.NewMessage(update.Message.Chat.ID, "")
	
	if validWord {
		// Generate username dari kata yang diberikan
		username := generateUsername(userWord)
		msg.Text = fmt.Sprintf("Username dari kata '%s': @%s", userWord, username)
	} else {
		msg.Text = "Kata tidak ditemukan dalam KBBI kami. Gunakan /generate untuk mendapatkan username secara acak."
	}
	
	if _, err := bot.Send(msg); err != nil {
		log.Printf("Error sending message: %v", err)
	}
}

func main() {
	// Set seed untuk random
	rand.Seed(time.Now().UnixNano())
	
	// Ambil token dari environment variable
	token := os.Getenv("TELEGRAM_BOT_TOKEN")
	if token == "" {
		log.Fatal("TELEGRAM_BOT_TOKEN tidak ditemukan")
	}
	
	bot, err := tgbotapi.NewBotAPI(token)
	if err != nil {
		log.Fatalf("Error initializing bot: %v", err)
	}
	
	log.Printf("Bot berhasil dimulai: %s", bot.Self.UserName)
	
	u := tgbotapi.NewUpdate(0)
	u.Timeout = 60
	
	updates := bot.GetUpdatesChan(u)
	
	for update := range updates {
		handleMessage(update, bot)
	}
}
