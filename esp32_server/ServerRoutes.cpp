#include "ServerRoutes.h"
#include <stdlib.h>
#include "Config.h"
#include "Types.h"
#include "Sensors.h"
#include "Actuators.h"
#include "AppNetwork.h"

static WebServer server(HTTP_PORT);

void sendJson(int code, const String &body) {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.send(code, "application/json; charset=utf-8", body);
}

// Một cảm biến MQ. adc là giá trị ADC thô 0..4095 (12 bit)
static void sendMq(const MqSensor &s) {
  char buf[256];
  snprintf(buf, sizeof(buf),
    "{\"key\":\"%s\",\"gas\":\"%s\",\"ppm\":%.1f,\"adc\":%d,"
    "\"r0\":%.2f,\"a\":%.3f,\"b\":%.3f,\"valid\":%s}",
    s.key, s.gas,
    s.ppm, s.adc, s.r0, s.a, s.b,
    boolStr(s.ppm >= 0));
  sendJson(200, buf);
}

static void handleMqList() {
  char buf[MQ_BUF_SIZE];
  size_t n = 0;
  n += snprintf(buf + n, sizeof(buf) - n, "{\"sensors\":[");
  for (int i = 0; i < MQ_COUNT; i++) {
    const MqSensor &s = mqs[i];
    n += snprintf(buf + n, sizeof(buf) - n,
      "%s{\"key\":\"%s\",\"gas\":\"%s\",\"ppm\":%.1f,\"adc\":%d,"
      "\"r0\":%.2f,\"a\":%.3f,\"b\":%.3f,\"valid\":%s}",
      i ? "," : "", s.key, s.gas,
      s.ppm, s.adc, s.r0, s.a, s.b,
      boolStr(s.ppm >= 0));
  }
  snprintf(buf + n, sizeof(buf) - n, "]}");
  sendJson(200, buf);
}

static void handleMqOne(const String &key) {
  for (const MqSensor &s : mqs) {
    if (key == s.key) { sendMq(s); return; }
  }
  sendJson(404, "{\"error\":\"Khong co cam bien nay\"}");
}

// JSON tong hop: dung chung cho GET /api/data va phan hoi sau khi dieu khien
void sendData() {
  char buf[DATA_BUF_SIZE];
  buildJson(buf, sizeof(buf), isWiFiConnected());
  sendJson(200, buf);
}

// -2 = sai tham so, -1 = auto, 0 = off, 1 = on. Nhan tu query hoac form body.
static int parseState() {
  String v = server.hasArg("state") ? server.arg("state") : server.arg("plain");
  v.trim();
  v.toLowerCase();

  if (v == "auto")                          return -1;
  if (v == "1" || v == "on"  || v == "true")  return 1;
  if (v == "0" || v == "off" || v == "false") return 0;
  return -2;
}

static void handleActuator(Actuator &a) {
  int mode = parseState();
  if (mode == -2) {
    sendJson(400, "{\"error\":\"Thieu state hoac sai gia tri. Dung ?state=on|off|auto\"}");
    return;
  }
  setActuator(a, mode);
  Serial.printf("[API] %s -> %s\n", a.name, mode < 0 ? "auto" : (mode ? "bat" : "tat"));
  sendData();
}

static void handleFirebaseState() {
  int mode = parseState();
  if (mode != 0 && mode != 1) {
    sendJson(400, "{\"error\":\"Chi nhan on|off|1|0|true|false\"}");
    return;
  }
  firebaseEnabled = (mode == 1);
  if (firebaseEnabled) {
    Serial.println("[FB] Bat dong bo");
    sendToFirebase();
  } else {
    Serial.println("[FB] Tat dong bo");
  }
  sendData();
}

static void handleThreshold() {
  if (!server.hasArg("key") || !server.hasArg("value")) {
    sendJson(400, "{\"error\":\"Can co key va value\"}");
    return;
  }

  float *slot = thresholdSlot(server.arg("key"));
  if (!slot) {
    sendJson(404, "{\"error\":\"Khong co chi so nay. Dung: mq135, mq2, mq7, pm2_5, pm10\"}");
    return;
  }

  String raw = server.arg("value");
  raw.trim();
  if (raw.length() == 0) {
    sendJson(400, "{\"error\":\"value rong\"}");
    return;
  }

  char *end = nullptr;
  float v = strtof(raw.c_str(), &end);
  if (end == raw.c_str() || *end != '\0' || v <= 0) {
    sendJson(400, "{\"error\":\"value phai la so > 0\"}");
    return;
  }

  *slot = v;
  Serial.printf("[API] Nguong %s -> %.1f\n", server.arg("key").c_str(), v);
  sendThresholdsToFirebase();
  sendData();
}

static void handleCalibrateInfo() {
  char buf[512];
  snprintf(buf, sizeof(buf),
    "{\"sensors\":["
    "{\"key\":\"mq135\",\"gas\":\"CO2\",\"r0\":%.2f,\"clean_air_ratio\":%.3f},"
    "{\"key\":\"mq2\",\"gas\":\"LPG\",\"r0\":%.2f,\"clean_air_ratio\":%.3f},"
    "{\"key\":\"mq7\",\"gas\":\"CO\",\"r0\":%.2f,\"clean_air_ratio\":%.3f}"
    "]}",
    mqs[MQ_CO2].r0, mqs[MQ_CO2].cleanAirRatio,
    mqs[MQ_LPG].r0, mqs[MQ_LPG].cleanAirRatio,
    mqs[MQ_CO].r0, mqs[MQ_CO].cleanAirRatio);
  sendJson(200, buf);
}

static void handleCalibrate() {
  int samples = 10;
  if (server.hasArg("samples")) {
    int s = server.arg("samples").toInt();
    if (s >= 1 && s <= 30) samples = s;
  }

  calibrateAllMqSensors(samples);

  char buf[512];
  snprintf(buf, sizeof(buf),
    "{\"success\":true,\"message\":\"Hieu chuan R0 ca 3 cam bien thanh cong\",\"sensors\":["
    "{\"key\":\"mq135\",\"gas\":\"CO2\",\"r0\":%.2f,\"clean_air_ratio\":%.3f},"
    "{\"key\":\"mq2\",\"gas\":\"LPG\",\"r0\":%.2f,\"clean_air_ratio\":%.3f},"
    "{\"key\":\"mq7\",\"gas\":\"CO\",\"r0\":%.2f,\"clean_air_ratio\":%.3f}"
    "]}",
    mqs[MQ_CO2].r0, mqs[MQ_CO2].cleanAirRatio,
    mqs[MQ_LPG].r0, mqs[MQ_LPG].cleanAirRatio,
    mqs[MQ_CO].r0, mqs[MQ_CO].cleanAirRatio);
  sendJson(200, buf);
}

void setupRoutes() {
  server.on("/api/data",      HTTP_GET,  sendData);
  server.on("/api/mq",        HTTP_GET,  handleMqList);
  server.on("/api/led",       HTTP_POST, []() { handleActuator(led); });
  server.on("/api/buzzer",    HTTP_POST, []() { handleActuator(buzzer); });
  server.on("/api/fan",       HTTP_POST, []() { handleActuator(fan); });
  server.on("/api/firebase",  HTTP_GET,  handleFirebaseState);
  server.on("/api/firebase",  HTTP_POST, handleFirebaseState);
  server.on("/api/threshold", HTTP_POST, handleThreshold);
  server.on("/api/calibrate", HTTP_GET,  handleCalibrateInfo);
  server.on("/api/calibrate", HTTP_POST, handleCalibrate);

  for (const MqSensor &s : mqs) {
    String key = s.key;
    server.on(String("/api/mq/") + key, HTTP_GET, [key]() { handleMqOne(key); });
  }

  server.onNotFound([]() { sendJson(404, "{\"error\":\"Khong tim thay endpoint\"}"); });

  server.begin();
}

void handleServerClient() {
  server.handleClient();
}
