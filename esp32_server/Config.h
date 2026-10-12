#pragma once

// ==========================================================
// 1. CẤU HÌNH HỆ THỐNG
// ==========================================================

// --- WiFi ---
#define WIFI_SSID     "HitroxVN"
#define WIFI_PASSWORD "passconcak"
#define WIFI_CONNECT_TIMEOUT_MS  20000
#define WIFI_RETRY_INTERVAL_MS   10000

// --- Firebase (LOCKED MODE - có xác thực) ---
#define FB_URL    "https://your-project-id.firebasedatabase.app"
#define FB_TOKEN  "Your_Firebase_Database_Secret"
#define FB_PATH_LATEST  "esp32/latest"   // ghi đè - luôn là mẫu mới nhất
#define FB_PATH_HISTORY "esp32/history"  // push  - lưu lại từng mẫu
#define FB_PATH_THRESHOLDS "esp32/thresholds" // lưu trữ các ngưỡng cảnh báo cài đặt
#define FB_SEND_INTERVAL_MS 30000         // gửi mỗi 30 giây, độc lập với chu kỳ đọc

// --- Pinout ngoại vi ---
#define DHT_PIN       4
#define DHT_TYPE      DHT22
#define MQ135_PIN     32
#define MQ2_PIN       35
#define MQ7_PIN       34
#define SDS_RX        16   // ESP32 RX2 nối SDS011 TX
#define SDS_TX        17   // ESP32 TX2 nối SDS011 RX
#define BUZZER_PIN    23
#define LED_PIN       21
#define FAN_PIN       18

// --- Web Server & Chu kỳ hoạt động ---
#define HTTP_PORT           80
#define SENSOR_INTERVAL_MS  3000
#define DATA_BUF_SIZE       1024
#define MQ_BUF_SIZE         768

// --- ADC ESP32 ---
#define BOARD_TYPE          "ESP-32"
#define VOLTAGE_RESOLUTION  3.3
#define ADC_BIT_RESOLUTION  12

// --- Hiệu chuẩn MQ: đường đặc tuyến ppm = a * (Rs/R0)^b ---
#define MQ135_A 110.47
#define MQ135_B -2.862
#define MQ135_R0 181.41
#define MQ2_A   574.25
#define MQ2_B   -2.222
#define MQ2_R0  14.45
#define MQ7_A   99.04
#define MQ7_B   -1.518
#define MQ7_R0  3.32

// --- Tỷ số Rs/R0 trong không khí sạch chuẩn (Datasheet) ---
#define RatioMQ135CleanAir      0.638 // Mốc 400 ppm CO2 tự nhiên
#define RatioMQ2CleanAir        9.83  // Datasheet LPG/Gas
#define RatioMQ7CleanAir        27.5  // Datasheet CO

// --- Ngưỡng cảnh báo mặc định ---
#define DEFAULT_THR_CO2   1500.0
#define DEFAULT_THR_LPG   25.0
#define DEFAULT_THR_CO    30.0
#define DEFAULT_THR_PM25  50.0
#define DEFAULT_THR_PM10  100.0
