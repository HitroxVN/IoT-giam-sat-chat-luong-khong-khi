#pragma once

#include <Arduino.h>
#include <MQUnifiedsensor.h>

// ==========================================================
// 2. KIỂU DỮ LIỆU & CẤU TRÚC HỆ THỐNG
// ==========================================================

// Thứ tự phần tử trong mảng mqs[]
enum { MQ_CO2, MQ_LPG, MQ_CO, MQ_COUNT };

// Cấu hình & trạng thái cảm biến MQ
struct MqSensor {
  MQUnifiedsensor *mq;
  const char *key;           // định danh URL, vd. "mq135"
  const char *type;          // tên hiệu thư viện, vd. "MQ-135"
  const char *gas;           // khí đo, vd. "CO2"
  uint8_t pin;
  float    a, b, r0;         // hệ số đặc tuyến và R0
  float    cleanAirRatio;    // tỷ số Rs/R0 trong không khí sạch
  float    thr;              // ngưỡng cảnh báo
  float    ppm;              // nồng độ đo được (âm: lỗi đọc)
  int      adc;              // ADC thô 0..4095
};

enum AlertLevel { ALERT_SAFE, ALERT_WARNING, ALERT_DANGER };

inline const char *alertLevelStr(AlertLevel lvl) {
  switch (lvl) {
    case ALERT_DANGER:  return "danger";
    case ALERT_WARNING: return "warning";
    default:            return "safe";
  }
}

inline const char *vnAqiCategoryStr(int aqi) {
  if (aqi < 0)    return "Chưa có";
  if (aqi <= 50)  return "Tốt";
  if (aqi <= 100) return "Trung bình";
  if (aqi <= 150) return "Kém";
  if (aqi <= 200) return "Xấu";
  if (aqi <= 300) return "Rất xấu";
  return "Nguy hại";
}

// Dữ liệu đọc môi trường & bụi
struct Reading {
  float tempC, humidity;
  float pm25, pm10;
  bool  envOk;      // DHT22 đọc thành công
  bool  dustOk;     // SDS011 trả frame hợp lệ
  bool  danger;     // có chỉ số vượt ngưỡng an toàn (tương thích ngược)
  AlertLevel alertLevel; // mức cảnh báo: ALERT_SAFE, ALERT_WARNING, ALERT_DANGER
  int   aqi;        // Chỉ số VN_AQI 
};

// Cơ cấu chấp hành (-1 = auto, 0 = tắt, 1 = bật)
struct Actuator {
  uint8_t     pin;
  int         mode;
  const char *name;
};
