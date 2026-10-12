#include "SerialReporter.h"
#include "Config.h"
#include "Types.h"
#include "Sensors.h"
#include "Actuators.h"

void printBanner() {
  Serial.println("\n==========================================");
  Serial.println("  ESP32 AIR QUALITY MONITOR SYSTEM READY  ");
  Serial.println("==========================================");
  for (const MqSensor &s : mqs) {
    Serial.printf("%-6s pin %2d  R0 %6.2f  Ratio %5.3f  a %.3f  b %.3f\n",
                  s.key, s.pin, s.r0, s.cleanAirRatio, s.a, s.b);
  }
  Serial.println("  [Tip] Go 'c' hoac 'calib' tren Serial de hieu chuan R0");
  Serial.println("==========================================");
}

void printReport() {
  Serial.println("\n------------------------------------------");
  Serial.println("[ MOI TRUONG - DHT22 ]");
  if (r.envOk) {
    Serial.printf("  %-18s %6.1f *C\n", "Nhiet do:", r.tempC);
    Serial.printf("  %-18s %6.1f %%\n",  "Do am:",    r.humidity);
  } else {
    Serial.println("  Loi: Khong doc duoc DHT22");
  }

  Serial.println("[ BUI MIN - SDS011 ]");
  if (r.dustOk) {
    Serial.printf("  %-18s %6.1f ug/m3\n", "PM2.5:", r.pm25);
    Serial.printf("  %-18s %6.1f ug/m3\n", "PM10:",  r.pm10);
    if (r.aqi >= 0) {
      Serial.printf("  %-18s %d (%s) [VN_AQI]\n", "VN_AQI:", r.aqi, vnAqiCategoryStr(r.aqi));
    }
  } else {
    Serial.println("  Dang doi frame du lieu SDS011...");
  }

  Serial.println("[ KHI DOC & O NHIEM - MQ ]");
  for (const MqSensor &s : mqs) {
    if (s.ppm < 0) {
      Serial.printf("  %-18s loi doc\n", (String(s.type) + ":").c_str());
    } else {
      Serial.printf("  %-18s %6.1f ppm   (ADC %d)\n", (String(s.type) + ":").c_str(), s.ppm, s.adc);
    }
  }

  Serial.println("[ TRANG THAI CANH BAO ]");
  if (r.alertLevel == ALERT_DANGER) {
    Serial.println("  [DANGER - NGUY HIEM] Chi so vuot nguong an toan!");
  } else if (r.alertLevel == ALERT_WARNING) {
    Serial.println("  [WARNING - CANH BAO] Chi so tiem can nguong (>= 80%)!");
  } else {
    Serial.println("  [SAFE - AN TOAN] Cac chi so trong muc binh thuong");
  }
  Serial.printf("  LED: %s | Buzzer: %s | Quat (D18): %s\n",
                digitalRead(LED_PIN) ? "ON" : "OFF",
                digitalRead(BUZZER_PIN) ? "ON" : "OFF",
                digitalRead(FAN_PIN) ? "ON" : "OFF");
  Serial.println("------------------------------------------");
}

void checkSerialCommand() {
  if (Serial.available()) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();
    cmd.toLowerCase();
    if (cmd == "c" || cmd == "calib" || cmd == "calibrate") {
      calibrateAllMqSensors(10);
    }
  }
}
