#include "AppNetwork.h"
#include "Sensors.h"
#include "Actuators.h"

// Chế độ LOCKED: luôn truyền token.
static Firebase fb(FB_URL, FB_TOKEN);

bool firebaseEnabled = true;
int  fbLastCode      = 0;      // mã HTTP của lần gửi gần nhất

const char *boolStr(bool b) { return b ? "true" : "false"; }

bool isWiFiConnected() {
  return WiFi.status() == WL_CONNECTED;
}

void connectWiFi() {
  if (isWiFiConnected()) return;

  Serial.printf("[WiFi] Dang ket noi toi \"%s\" ...\n", WIFI_SSID);

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  unsigned long start = millis();
  while (!isWiFiConnected() && millis() - start < WIFI_CONNECT_TIMEOUT_MS) {
    delay(250);
  }

  if (isWiFiConnected()) {
    Serial.printf("[WiFi] OK - IP: %s\n", WiFi.localIP().toString().c_str());
    Serial.printf("[HTTP] Server: http://%s:%d\n", WiFi.localIP().toString().c_str(), HTTP_PORT);
  } else {
    Serial.println("[WiFi] That bai - se thu lai sau.");
  }
}

// Cùng nội dung với JSON của GET /api/data - một nguồn sự thật.
void buildJson(char *buf, size_t n, bool wifi) {
  snprintf(buf, n,
    "{\"device\":\"esp32-air-quality\",\"uptime_ms\":%lu,"
    "\"wifi\":{\"connected\":%s,\"ssid\":\"%s\",\"rssi\":%d},"
    "\"env\":{\"valid\":%s,\"temp_c\":%.2f,\"humidity\":%.2f},"
    "\"dust\":{\"valid\":%s,\"pm2_5\":%.1f,\"pm10\":%.1f},"
    "\"gas\":{\"co2_ppm\":%.1f,\"lpg_ppm\":%.1f,\"co_ppm\":%.1f},"
    "\"aqi\":{\"value\":%d,\"category\":\"%s\"},"
    "\"alert\":{\"level\":\"%s\",\"danger\":%s,\"led\":%d,\"buzzer\":%d,\"fan\":%d},"
    "\"firebase\":{\"enabled\":%s,\"last_code\":%d,\"interval_ms\":%lu},"
    "\"thresholds\":{\"co2\":%.0f,\"lpg\":%.0f,\"co\":%.0f,\"pm2_5\":%.0f,\"pm10\":%.0f}}",
    millis(),
    boolStr(wifi), WIFI_SSID, wifi ? WiFi.RSSI() : 0,
    boolStr(r.envOk), r.envOk ? r.tempC : 0.0, r.envOk ? r.humidity : 0.0,
    boolStr(r.dustOk), r.pm25, r.pm10,
    mqs[MQ_CO2].ppm, mqs[MQ_LPG].ppm, mqs[MQ_CO].ppm,
    r.aqi, vnAqiCategoryStr(r.aqi),
    alertLevelStr(r.alertLevel), boolStr(r.danger),
    digitalRead(LED_PIN), digitalRead(BUZZER_PIN), digitalRead(FAN_PIN),
    boolStr(firebaseEnabled), fbLastCode, (unsigned long)FB_SEND_INTERVAL_MS,
    mqs[MQ_CO2].thr, mqs[MQ_LPG].thr, mqs[MQ_CO].thr, thrPm25, thrPm10);
}

void sendToFirebase() {
  if (!firebaseEnabled) return;

  // Không gửi khi mất WiFi - request sẽ chỉ chờ rồi timeout, chặn loop().
  if (!isWiFiConnected()) {
    Serial.println("[FB] Bo qua: chua co WiFi");
    return;
  }

  char buf[DATA_BUF_SIZE];
  buildJson(buf, sizeof(buf), true);

  int code = fb.setJson(FB_PATH_LATEST, buf);   // ghi đè
  Serial.printf("[FB] latest -> %d\n", code);

  // History trả về mã khác 200 nếu không ghi được; không chặn latest.
  int hcode = fb.pushJson(FB_PATH_HISTORY, buf);
  if (hcode != 200) Serial.printf("[FB] history -> %d\n", hcode);

  // Chỉ giữ mã của latest để báo trạng thái.
  fbLastCode = code;
}

static float parseJsonFloat(const String &json, const char *key) {
  String searchKey = String("\"") + key + "\"";
  int idx = json.indexOf(searchKey);
  if (idx < 0) return -1.0f;
  idx = json.indexOf(':', idx + searchKey.length());
  if (idx < 0) return -1.0f;
  idx++;
  while (idx < (int)json.length() && (json[idx] == ' ' || json[idx] == '\t' || json[idx] == '"')) {
    idx++;
  }
  return json.substring(idx).toFloat();
}

void sendThresholdsToFirebase() {
  if (!firebaseEnabled) return;
  if (!isWiFiConnected()) {
    Serial.println("[FB] Khong the gui nguong: chua co WiFi");
    return;
  }

  char buf[256];
  snprintf(buf, sizeof(buf),
    "{\"co2\":%.0f,\"lpg\":%.0f,\"co\":%.0f,\"pm2_5\":%.0f,\"pm10\":%.0f}",
    mqs[MQ_CO2].thr, mqs[MQ_LPG].thr, mqs[MQ_CO].thr, thrPm25, thrPm10);

  int code = fb.setJson(FB_PATH_THRESHOLDS, buf);
  Serial.printf("[FB] thresholds -> %d\n", code);
}

void syncThresholdsFromFirebase() {
  if (!firebaseEnabled || !isWiFiConnected()) return;

  Serial.println("[FB] Dang kiem tra nguong tu Firebase (" FB_PATH_THRESHOLDS ") ...");
  String res;
  int code = fb.getJson(FB_PATH_THRESHOLDS, res);
  res.trim();
  if (code == 200 && res.length() > 0 && res != "null") {
    float co2  = parseJsonFloat(res, "co2");
    float lpg  = parseJsonFloat(res, "lpg");
    float co   = parseJsonFloat(res, "co");
    float pm25 = parseJsonFloat(res, "pm2_5");
    float pm10 = parseJsonFloat(res, "pm10");

    bool updated = false;
    if (co2 > 0)  { mqs[MQ_CO2].thr = co2;  updated = true; }
    if (lpg > 0)  { mqs[MQ_LPG].thr = lpg;  updated = true; }
    if (co > 0)   { mqs[MQ_CO].thr  = co;   updated = true; }
    if (pm25 > 0) { thrPm25         = pm25; updated = true; }
    if (pm10 > 0) { thrPm10         = pm10; updated = true; }

    if (updated) {
      Serial.printf("[FB] Da dong bo nguong tu Firebase: CO2=%.0f, LPG=%.0f, CO=%.0f, PM2.5=%.0f, PM10=%.0f\n",
                    mqs[MQ_CO2].thr, mqs[MQ_LPG].thr, mqs[MQ_CO].thr, thrPm25, thrPm10);
    }
  } else {
    // Neu tren Firebase chua co node thresholds (tra ve "null"), day nguong mac dinh len
    Serial.println("[FB] Chua co nguong tren Firebase, dang day nguong mac dinh len...");
    sendThresholdsToFirebase();
  }
}
