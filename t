import asyncio
import time
import re
import aiosqlite
from collections import defaultdict, deque
from pyrogram import Client, filters
from pyrogram.types import Message, InlineKeyboardMarkup, InlineKeyboardButton, CallbackQuery
from pyrogram.idle import idle
import datetime

# === Konfigurasi Bot ===
api_id = 123456  # Ganti dengan API ID Anda
api_hash = "your_api_hash"
bot_token = "your_bot_token"
channel_username = "t.me/yourchannel"  # Channel yang wajib diikuti
DEVELOPER_IDS = [123456789]  # Ganti dengan user_id developer permanen

# === Inisialisasi Client ===
app = Client("super_antispam_bot", api_id=api_id, api_hash=api_hash, bot_token=bot_token)

# === Deteksi Flood & Duplikat ===
user_messages = defaultdict(lambda: deque(maxlen=10))
group_settings = defaultdict(lambda: {
    "spam_sensitivity": 4,  # Berapa pesan berulang dalam waktu singkat dianggap spam
    "flood_time_window": 3,  # Jendela waktu (detik) untuk mendeteksi flood
    "text_similarity_threshold": 0.8,  # Threshold kemiripan teks (0-1)
    "auto_delete_commands": True,  # Auto hapus pesan command setelah diproses
    "intelligent_filter": True,  # Aktifkan filter cerdas berbasis ML
    "remove_links": True,  # Hapus pesan dengan link kecuali whitelist 
    "remove_forwards": False,  # Hapus pesan yang diforward
    "log_channel": # === Handler Pesan Grup ===
@app.on_message(filters.group)
async def group_handler(client: Client, message: Message):
    if not await is_antispam_enabled(message.chat.id):
        return

    # Skip jika admin atau developer
    if hasattr(message, 'from_user') and message.from_user and await is_admin(message):
        return
    
    # Skip jika tidak ada user (misalnya welcome messages)
    if not hasattr(message, 'from_user') or not  # ID channel untuk logging aktivitas
})

# Cache status antispam per grup
antispam_status_cache = {}

# === Deteksi Link ===
URL_PATTERN = re.compile(r'(https?://\S+|www\.\S+|t\.me/\S+)')

# === Link Whitelist ===
whitelisted_domains = ["telegram.org", "t.me"]

# === Inisialisasi Database ===
async def init_db():
    try:
        async with aiosqlite.connect("antispam.db") as db:
            # Tabel utama
            await db.execute("CREATE TABLE IF NOT EXISTS blacklist_users (user_id INTEGER PRIMARY KEY)")
            await db.execute("CREATE TABLE IF NOT EXISTS whitelist_users (user_id INTEGER PRIMARY KEY)")
            await db.execute("CREATE TABLE IF NOT EXISTS blacklist_texts (text TEXT PRIMARY KEY)")
            await db.execute("CREATE TABLE IF NOT EXISTS whitelist_texts (text TEXT PRIMARY KEY)")
            await db.execute("CREATE TABLE IF NOT EXISTS antispam_status (chat_id INTEGER PRIMARY KEY, enabled INTEGER)")
            
            # Tabel tambahan untuk fitur advanced
            await db.execute("""CREATE TABLE IF NOT EXISTS group_settings (
                chat_id INTEGER PRIMARY KEY,
                spam_sensitivity INTEGER DEFAULT 4,
                flood_time_window INTEGER DEFAULT 3,
                text_similarity_threshold REAL DEFAULT 0.8,
                auto_delete_commands INTEGER DEFAULT 1,
                intelligent_filter INTEGER DEFAULT 1,
                remove_links INTEGER DEFAULT 1,
                remove_forwards INTEGER DEFAULT 0,
                log_channel INTEGER DEFAULT NULL
            )""")
            
            await db.execute("CREATE TABLE IF NOT EXISTS whitelist_domains (domain TEXT PRIMARY KEY)")
            
            # Tabel untuk pattern deteksi
            await db.execute("CREATE TABLE IF NOT EXISTS pattern_filters (pattern TEXT PRIMARY KEY, description TEXT)")
            
            # Tabel untuk logging dan statistik
            await db.execute("""CREATE TABLE IF NOT EXISTS spam_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                chat_id INTEGER,
                user_id INTEGER,
                message_type TEXT,
                detection_type TEXT,
                content TEXT,
                timestamp INTEGER
            )""")
            
            # Memastikan ada domain whitelist default
            await db.execute("INSERT OR IGNORE INTO whitelist_domains (domain) VALUES ('telegram.org')")
            await db.execute("INSERT OR IGNORE INTO whitelist_domains (domain) VALUES ('t.me')")
            
            # Menambahkan beberapa pola regex default untuk spam
            await db.execute("INSERT OR IGNORE INTO pattern_filters (pattern, description) VALUES ('^.*(join|invite|promo|gratis|free money).*$', 'Promotional spam')")
            await db.execute("INSERT OR IGNORE INTO pattern_filters (pattern, description) VALUES ('.*make money fast.*', 'Scam message')")
            
            await db.commit()
    except Exception as e:
        print(f"Error initializing database: {e}")
        raise

# === Cek DB ===
async def check_db(table: str, key: str, value):
    async with aiosqlite.connect("antispam.db") as db:
        async with db.execute(f"SELECT 1 FROM {table} WHERE {key} = ?", (value,)) as cursor:
            return await cursor.fetchone() is not None

async def add_to_db(table: str, key: str, value):
    async with aiosqlite.connect("antispam.db") as db:
        await db.execute(f"INSERT OR IGNORE INTO {table} ({key}) VALUES (?)", (value,))
        await db.commit()

async def remove_from_db(table: str, key: str, value):
    async with aiosqlite.connect("antispam.db") as db:
        await db.execute(f"DELETE FROM {table} WHERE {key} = ?", (value,))
        await db.commit()
        
# === Fungsi Helper Untuk Pengaturan Grup ===
async def get_group_settings(chat_id: int) -> dict:
    # Cek cache dahulu
    if chat_id in group_settings:
        return group_settings[chat_id]
    
    # Jika tidak ada di cache, ambil dari database
    async with aiosqlite.connect("antispam.db") as db:
        async with db.execute(
            "SELECT spam_sensitivity, flood_time_window, text_similarity_threshold, auto_delete_commands, intelligent_filter, remove_links, remove_forwards, log_channel FROM group_settings WHERE chat_id = ?", 
            (chat_id,)
        ) as cursor:
            row = await cursor.fetchone()
            
            if row:
                settings = {
                    "spam_sensitivity": row[0],
                    "flood_time_window": row[1],
                    "text_similarity_threshold": row[2],
                    "auto_delete_commands": bool(row[3]),
                    "intelligent_filter": bool(row[4]),
                    "remove_links": bool(row[5]),
                    "remove_forwards": bool(row[6]),
                    "log_channel": row[7]
                }
                # Update cache
                group_settings[chat_id] = settings
                return settings
    
    # Jika setting belum ada di database, gunakan default dan simpan ke DB
    settings = group_settings.default_factory()
    async with aiosqlite.connect("antispam.db") as db:
        await db.execute(
            "INSERT INTO group_settings (chat_id, spam_sensitivity, flood_time_window, text_similarity_threshold, auto_delete_commands, intelligent_filter, remove_links, remove_forwards) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (chat_id, settings["spam_sensitivity"], settings["flood_time_window"], settings["text_similarity_threshold"], 
             int(settings["auto_delete_commands"]), int(settings["intelligent_filter"]), int(settings["remove_links"]), int(settings["remove_forwards"]))
        )
        await db.commit()
    
    # Update cache
    group_settings[chat_id] = settings
    return settings

async def update_group_setting(chat_id: int, setting: str, value):
    # Update di database
    async with aiosqlite.connect("antispam.db") as db:
        await db.execute(f"UPDATE group_settings SET {setting} = ? WHERE chat_id = ?", (value, chat_id))
        await db.commit()
    
    # Update cache jika ada
    if chat_id in group_settings:
        group_settings[chat_id][setting] = value

# === Cek Antispam Aktif (dengan cache) ===
async def is_antispam_enabled(chat_id: int) -> bool:
    # Cek di cache dulu untuk kecepatan
    if chat_id in antispam_status_cache:
        return antispam_status_cache[chat_id]
    
    # Jika tidak ada di cache, cek di database
    async with aiosqlite.connect("antispam.db") as db:
        async with db.execute("SELECT enabled FROM antispam_status WHERE chat_id = ?", (chat_id,)) as cursor:
            row = await cursor.fetchone()
            status = row and row[0] == 1
            # Simpan ke cache
            antispam_status_cache[chat_id] = status
            return status

# === Fungsi Utilitas ===
async def log_spam_detection(chat_id: int, user_id: int, message_type: str, detection_type: str, content: str):
    """Mencatat aktivitas spam ke database untuk analisis dan statistik"""
    settings = await get_group_settings(chat_id)
    timestamp = int(time.time())
    
    # Simpan log ke database
    async with aiosqlite.connect("antispam.db") as db:
        await db.execute(
            "INSERT INTO spam_logs (chat_id, user_id, message_type, detection_type, content, timestamp) VALUES (?, ?, ?, ?, ?, ?)",
            (chat_id, user_id, message_type, detection_type, content, timestamp)
        )
        await db.commit()
    
    # Jika grup memiliki log channel, kirim notifikasi
    log_channel = settings.get("log_channel")
    if log_channel:
        try:
            message = f"🛡 **Spam Terdeteksi**\n" \
                      f"• **Grup ID:** `{chat_id}`\n" \
                      f"• **User ID:** `{user_id}`\n" \
                      f"• **Jenis:** {detection_type}\n" \
                      f"• **Waktu:** {datetime.datetime.fromtimestamp(timestamp).strftime('%Y-%m-%d %H:%M:%S')}\n" \
                      f"• **Konten:** ```{content[:100]}{'...' if len(content) > 100 else ''}```"
            await app.send_message(log_channel, message)
        except Exception as e:
            print(f"Error sending log message: {e}")

def calculate_text_similarity(text1: str, text2: str) -> float:
    """Menghitung kemiripan antara dua teks (algoritma simple menggunakan karakter yang sama)"""
    if not text1 or not text2:
        return 0.0
        
    # Normalisasi teks - ubah ke lowercase dan hapus spasi berlebih
    text1 = " ".join(text1.lower().split())
    text2 = " ".join(text2.lower().split())
    
    # Untuk teks pendek, gunakan direct matching
    if len(text1) < 10 or len(text2) < 10:
        return 1.0 if text1 == text2 else 0.0
    
    # Untuk teks yang panjangnya berbeda jauh, similarity rendah
    if min(len(text1), len(text2)) / max(len(text1), len(text2)) < 0.5:
        return 0.0
    
    # Hitung karakter yang sama di posisi yang sama
    match_chars = sum(1 for a, b in zip(text1, text2) if a == b)
    
    # Hitung similarity berdasarkan rata-rata panjang teks
    avg_length = (len(text1) + len(text2)) / 2
    return match_chars / avg_length if avg_length > 0 else 0.0

def contains_blacklisted_pattern(text: str) -> bool:
    """Cek apakah teks mengandung pola yang dianggap spam"""
    # Ini bisa diimplementasikan dengan regex dari database
    # Untuk sekarang, gunakan pola sederhana
    spam_patterns = [
        r'join\s+.*channel',
        r'free\s+money',
        r'earn\s+bitcoin',
        r'invest\s+now',
        r'make\s+\d+\s*[k$]',
        r'dating\s+site',
        r'adult\s+content',
        r'\+\d{10,}',  # Nomor telepon
    ]
    
    text_lower = text.lower()
    return any(re.search(pattern, text_lower) for pattern in spam_patterns)

def contains_url(text: str) -> bool:
    """Deteksi apakah teks mengandung URL"""
    return bool(URL_PATTERN.search(text))

# === Cek Admin atau Developer ===
async def is_admin(message: Message) -> bool:
    if message.from_user.id in DEVELOPER_IDS:
        return True
    try:
        member = await app.get_chat_member(message.chat.id, message.from_user.id)
        return member.status in ("administrator", "creator")
    except Exception:
        return False

# === Deteksi Flood ===
def is_flood(user_id: int, text: str, chat_id: int) -> bool:
    """Deteksi flood berdasarkan pengaturan grup"""
    settings = group_settings.get(chat_id, group_settings.default_factory())
    sensitivity = settings["spam_sensitivity"]
    time_window = settings["flood_time_window"]
    
    now = time.time()
    q = user_messages[user_id]
    
    # Tambahkan pesan baru
    q.append((text, now))
    
    # Hapus pesan lama (lebih dari time_window detik)
    while q and now - q[0][1] > time_window:
        q.popleft()
    
    # Hitung berapa kali pesan yang sama atau mirip muncul
    similar_msgs = 0
    similarity_threshold = settings["text_similarity_threshold"]
    
    for old_text, _ in q:
        if old_text == text or calculate_text_similarity(old_text, text) >= similarity_threshold:
            similar_msgs += 1
    
    return similar_msgs >= sensitivity

# === Handler Pesan Grup ===
@app.on_message(filters.text & filters.group)
async def group_handler(client: Client, message: Message):
    if not await is_antispam_enabled(message.chat.id):
        return

    user_id = message.from_user.id
    text = message.text.strip()

    # Skip jika admin atau developer
    if await is_admin(message):
        return

    # Cek blacklist user (kecuali jika di whitelist)
    if await check_db("blacklist_users", "user_id", user_id) and not await check_db("whitelist_users", "user_id", user_id):
        await message.delete()
        return

    # Cek blacklist text (kecuali jika di whitelist)
    if await check_db("blacklist_texts", "text", text) and not await check_db("whitelist_texts", "text", text):
        await message.delete()
        return

    # Cek duplikat (pesan yang sama dari user yang sama)
    if any(text == msg for msg, _ in user_messages[user_id]):
        await message.delete()
        return

    # Cek flood
    if is_flood(user_id, text):
        await message.delete()
        return

# === Command Admin ===
@app.on_message(filters.command([
    "on", "off", "addblacklistuser", "addwhitelistuser", 
    "addblacklisttext", "addwhitelisttext", "removeblacklistuser", 
    "removewhitelistuser", "removeblacklisttext", "removewhitelisttext"
]) & filters.group)
async def admin_commands(client: Client, message: Message):
    if not await is_admin(message):
        return

    cmd = message.command[0]
    args = message.command[1:]
    reply = message.reply_to_message

    if cmd in ["on", "off"]:
        status = 1 if cmd == "on" else 0
        async with aiosqlite.connect("antispam.db") as db:
            await db.execute("INSERT OR REPLACE INTO antispam_status (chat_id, enabled) VALUES (?, ?)", (message.chat.id, status))
            await db.commit()
        text = "Anti-spam diaktifkan." if status else "Anti-spam dimatikan."
        notice = await message.reply(text)

    elif cmd in ["addblacklistuser", "addwhitelistuser", "removeblacklistuser", "removewhitelistuser"] and reply:
        target_id = reply.from_user.id
        table = "blacklist_users" if "blacklist" in cmd else "whitelist_users"
        
        if cmd.startswith("add"):
            await add_to_db(table, "user_id", target_id)
            action = "ditambahkan ke"
        else:
            await remove_from_db(table, "user_id", target_id)
            action = "dihapus dari"
            
        notice = await message.reply(f"User berhasil {action} {table}.")

    elif cmd in ["addblacklisttext", "addwhitelisttext", "removeblacklisttext", "removewhitelisttext"]:
        if reply and reply.text:
            text = reply.text
        elif args:
            text = " ".join(args)
        else:
            return await message.reply("Reply ke pesan atau berikan teks sebagai argumen.")
            
        table = "blacklist_texts" if "blacklist" in cmd else "whitelist_texts"
        
        if cmd.startswith("add"):
            await add_to_db(table, "text", text)
            action = "ditambahkan ke"
        else:
            await remove_from_db(table, "text", text)
            action = "dihapus dari"
            
        notice = await message.reply(f"Teks berhasil {action} {table}.")

    else:
        return

    await asyncio.sleep(2)
    await notice.delete()
    await message.delete()

# === /start di Private ===
@app.on_message(filters.command("start") & filters.private)
async def start_handler(client: Client, message: Message):
    user_id = message.from_user.id
    welcome = await message.reply("Halo selamat datang")
    await asyncio.sleep(3)
    await welcome.delete()

    try:
        member = await client.get_chat_member(channel_username, user_id)
        if member.status not in ["member", "administrator", "creator"]:
            raise Exception()
    except:
        btn = InlineKeyboardMarkup([[InlineKeyboardButton("Join Dulu", url=f"https://{channel_username}")]])
        return await message.reply("Silakan join channel dulu.", reply_markup=btn)

    menu = InlineKeyboardMarkup([
        [InlineKeyboardButton("Help", callback_data="help")],
        [
            InlineKeyboardButton("Support", url="https://t.me/ariaxsupportbot"),
            InlineKeyboardButton("Owner", url="https://t.me/ampud")
        ],
        [InlineKeyboardButton("Close", callback_data="close")]
    ])
    await message.reply("Selamat datang! Silakan pilih menu:", reply_markup=menu)

# === Callback Handler ===
@app.on_callback_query(filters.regex("^(help|close|back)$"))
async def callback_handler(client: Client, callback_query: CallbackQuery):
    data = callback_query.data
    await callback_query.answer()
    
    if data == "help":
        help_text = (
            "**Cara Menggunakan Bot:**\n"
            "- Bot akan otomatis menghapus spam, flood, dan pesan duplikat\n"
            "- Gunakan perintah berikut di grup (admin/dev):\n"
            "/on atau /off - Aktif/nonaktifkan antispam\n"
            "/addblacklistuser [reply] - Blacklist user\n"
            "/addwhitelistuser [reply] - Whitelist user\n" 
            "/removeblacklistuser [reply] - Hapus user dari blacklist\n"
            "/removewhitelistuser [reply] - Hapus user dari whitelist\n"
            "/addblacklisttext [reply/text] - Blacklist teks\n"
            "/addwhitelisttext [reply/text] - Whitelist teks\n"
            "/removeblacklisttext [reply/text] - Hapus teks dari blacklist\n"
            "/removewhitelisttext [reply/text] - Hapus teks dari whitelist"
        )
        
        keyboard = InlineKeyboardMarkup([
            [InlineKeyboardButton("Back", callback_data="back")],
            [InlineKeyboardButton("Close", callback_data="close")]
        ])
        
        await callback_query.message.edit_text(help_text, reply_markup=keyboard)
    
    elif data == "back":
        menu = InlineKeyboardMarkup([
            [InlineKeyboardButton("Help", callback_data="help")],
            [
                InlineKeyboardButton("Support", url="https://t.me/ariaxsupportbot"),
                InlineKeyboardButton("Owner", url="https://t.me/ampud")
            ],
            [InlineKeyboardButton("Close", callback_data="close")]
        ])
        await callback_query.message.edit_text("Selamat datang! Silakan pilih menu:", reply_markup=menu)
    
    elif data == "close":
        try:
            await callback_query.message.delete()
        except Exception:
            pass

# === Main ===
async def main():
    await init_db()
    await app.start()
    print("Bot aktif.")
    await idle()
    await app.stop()

if __name__ == "__main__":
    asyncio.run(main())