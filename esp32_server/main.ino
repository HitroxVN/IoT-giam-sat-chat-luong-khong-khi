/**
 * ============================================================================
 * DỰ ÁN GIÁM SÁT CHẤT LƯỢNG KHÔNG KHÍ (ESP32 AIR QUALITY MONITOR)
 * ============================================================================
 * Các module độc lập:
 *  - Config.h         : Định nghĩa toàn bộ chân GPIO, WiFi, Firebase, hệ số MQ.
 *  - Types.h          : Định nghĩa struct (MqSensor, Reading, Actuator) & enum.
 *  - Actuators.h/.cpp : Điều khiển phần cứng đầu ra (LED, Buzzer, Quạt D18).
 *  - Sensors.h/.cpp   : Thu thập & hiệu chuẩn cảm biến (DHT22, SDS011, MQ-135, MQ-2, MQ-7).
 *  - Network.h/.cpp   : Quản lý WiFi, đồng bộ Firebase Realtime Database.
 *  - ServerRoutes.h/.cpp : Xử lý REST API (CORS, JSON, GET/POST endpoints).
 *  - SerialReporter.h/.cpp : Giao diện log Serial Monitor & lệnh tương tác.
 * ============================================================================
 */

#include <Arduino.h>
#include "Config.h"
#include "Types.h"
#include "Actuators.h"
#include "Sensors.h"
#include "AppNetwork.h"
#include "ServerRoutes.h"
#include "SerialReporter.h"

// Bộ đếm thời gian chu kỳ
static unsigned long lastSensorRead   = 0;
static unsigned long lastWifiAttempt  = 0;
static unsigned long lastFirebaseSend = 0;

void setup() {
  Serial.begin(115200);

  // 1. Khởi tạo phần cứng
  setupActuators();
  setupSensors();
  printBanner();

  // 2. Kết nối mạng & khởi động Web Server
  connectWiFi();
  lastWifiAttempt = millis();
  setupRoutes();
  syncThresholdsFromFirebase();

  // 3. Lấy mẫu đầu tiên và đồng bộ ngay khi khởi động
  sampleSensors();
  lastSensorRead = millis();
  applyAlertToPins();
  printReport();

  sendToFirebase();
  lastFirebaseSend = millis();
}

void loop() {
  // Xử lý request HTTP từ client và lệnh Serial từ người dùng
  handleServerClient();
  checkSerialCommand();

  unsigned long now = millis();

  // 1. Chu kỳ đọc cảm biến & cập nhật cảnh báo (mỗi 3 giây)
  if (now - lastSensorRead >= SENSOR_INTERVAL_MS) {
    lastSensorRead = now;
    sampleSensors();
    applyAlertToPins();
    printReport();
  }

  // 2. Chu kỳ đẩy dữ liệu lên Firebase (mỗi 30 giây)
  if (now - lastFirebaseSend >= FB_SEND_INTERVAL_MS) {
    lastFirebaseSend = now;
    sendToFirebase();
  }

  // 3. Tự động kết nối lại WiFi nếu mất kết nối (mỗi 10 giây)
  if (!isWiFiConnected() && (now - lastWifiAttempt >= WIFI_RETRY_INTERVAL_MS)) {
    lastWifiAttempt = now;
    connectWiFi();
  }

  delay(2);
}