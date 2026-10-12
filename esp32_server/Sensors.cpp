#include "Sensors.h"

// --- Đối tượng phần cứng cảm biến ---
DHT           dht(DHT_PIN, DHT_TYPE);
HardwareSerial sds(2);

MQUnifiedsensor mq135(BOARD_TYPE, VOLTAGE_RESOLUTION, ADC_BIT_RESOLUTION, MQ135_PIN, "MQ-135");
MQUnifiedsensor mq2  (BOARD_TYPE, VOLTAGE_RESOLUTION, ADC_BIT_RESOLUTION, MQ2_PIN,   "MQ-2");
MQUnifiedsensor mq7  (BOARD_TYPE, VOLTAGE_RESOLUTION, ADC_BIT_RESOLUTION, MQ7_PIN,   "MQ-7");

MqSensor mqs[MQ_COUNT] = {
  {&mq135, "mq135", "MQ-135", "CO2", MQ135_PIN, MQ135_A, MQ135_B, MQ135_R0, RatioMQ135CleanAir, DEFAULT_THR_CO2, 0, 0},
  {&mq2,   "mq2",   "MQ-2",   "LPG", MQ2_PIN,   MQ2_A,   MQ2_B,   MQ2_R0,   RatioMQ2CleanAir,   DEFAULT_THR_LPG, 0, 0},
  {&mq7,   "mq7",   "MQ-7",   "CO",  MQ7_PIN,   MQ7_A,   MQ7_B,   MQ7_R0,   RatioMQ7CleanAir,   DEFAULT_THR_CO,  0, 0},
};

Reading r = {NAN, NAN, 0, 0, false, false, false, ALERT_SAFE, -1};

// Ngưỡng bụi (ug/m3)
float thrPm25 = DEFAULT_THR_PM25;
float thrPm10 = DEFAULT_THR_PM10;

void setupSensors() {
  analogReadResolution(ADC_BIT_RESOLUTION);
  analogSetAttenuation(ADC_11db);

  dht.begin();
  sds.begin(9600, SERIAL_8N1, SDS_RX, SDS_TX);

  for (const MqSensor &s : mqs) {
    s.mq->setRegressionMethod(1);   // đường đặc tuyến lũy thừa
    s.mq->setA(s.a);
    s.mq->setB(s.b);
    s.mq->init();
    s.mq->setR0(s.r0);
  }
}

// SDS011: khung 10 byte, byte đầu 0xAA, lệnh 0xC0, checksum = tổng byte 2..7.
bool readSDS(float &pm25, float &pm10) {
  while (sds.available() >= 10) {
    if (sds.read() != 0xAA) continue;

    uint8_t b[10];
    b[0] = 0xAA;
    for (int i = 1; i < 10; i++) b[i] = sds.read();
    if (b[1] != 0xC0) continue;

    uint8_t sum = 0;
    for (int i = 2; i <= 7; i++) sum += b[i];
    if (sum != b[8]) return false;

    pm25 = ((uint16_t)b[2] | ((uint16_t)b[3] << 8)) / 10.0;
    pm10 = ((uint16_t)b[4] | ((uint16_t)b[5] << 8)) / 10.0;
    return true;
  }
  return false;
}

// ==========================================================
// TÍNH TOÁN CHỈ SỐ VN_AQI 
// ==========================================================
struct VnAqiBreakpoint {
  int i_lo, i_hi;
  float bp_lo, bp_hi;
};

// Bảng BP PM2.5 (ug/m3)
static const VnAqiBreakpoint BP_VN_PM25[] = {
  {0,   50,  0.0f,   25.0f},
  {51,  100, 25.1f,  50.0f},
  {101, 150, 50.1f,  80.0f},
  {151, 200, 80.1f,  150.0f},
  {201, 300, 150.1f, 250.0f},
  {301, 400, 250.1f, 350.0f},
  {401, 500, 350.1f, 500.0f}
};

// Bảng BP PM10 (ug/m3) theo QĐ 1459/QĐ-TCMT
static const VnAqiBreakpoint BP_VN_PM10[] = {
  {0,   50,  0.0f,   50.0f},
  {51,  100, 50.1f,  150.0f},
  {101, 150, 150.1f, 250.0f},
  {151, 200, 250.1f, 350.0f},
  {201, 300, 350.1f, 420.0f},
  {301, 400, 420.1f, 500.0f},
  {401, 500, 500.1f, 600.0f}
};

// Bảng BP CO (ug/m3) theo QĐ 1459/QĐ-TCMT (1 ppm CO ~ 1145 ug/m3)
static const VnAqiBreakpoint BP_VN_CO[] = {
  {0,   50,  0.0f,     10000.0f},
  {51,  100, 10001.0f, 30000.0f},
  {101, 150, 30001.0f, 45000.0f},
  {151, 200, 45001.0f, 60000.0f},
  {201, 300, 60001.0f, 90000.0f},
  {301, 400, 90001.0f, 120000.0f},
  {401, 500, 120001.0f, 150000.0f}
};

static int calcSingleVnAqi(float c, const VnAqiBreakpoint bps[], size_t count) {
  if (c <= 0.0f) return 0;
  for (size_t i = 0; i < count; i++) {
    if (c <= bps[i].bp_hi) {
      float spanBp = bps[i].bp_hi - bps[i].bp_lo;
      if (spanBp <= 0.0f) return bps[i].i_lo;
      float aqi = ((float)(bps[i].i_hi - bps[i].i_lo) / spanBp) * (c - bps[i].bp_lo) + bps[i].i_lo;
      return (int)round(aqi);
    }
  }
  return bps[count - 1].i_hi; // Tối đa 500
}

int computeVnAqi(bool dustOk, float pm25, float pm10, float co_ppm) {
  if (!dustOk || (pm25 < 0.0f && pm10 < 0.0f)) {
    return -1;
  }

  int aqiMax = 0;
  if (pm25 >= 0.0f) {
    int aqiPm25 = calcSingleVnAqi(pm25, BP_VN_PM25, sizeof(BP_VN_PM25) / sizeof(BP_VN_PM25[0]));
    if (aqiPm25 > aqiMax) aqiMax = aqiPm25;
  }
  if (pm10 >= 0.0f) {
    int aqiPm10 = calcSingleVnAqi(pm10, BP_VN_PM10, sizeof(BP_VN_PM10) / sizeof(BP_VN_PM10[0]));
    if (aqiPm10 > aqiMax) aqiMax = aqiPm10;
  }
  if (co_ppm > 0.0f) {
    float co_ugm3 = co_ppm * 1145.0f;
    int aqiCo = calcSingleVnAqi(co_ugm3, BP_VN_CO, sizeof(BP_VN_CO) / sizeof(BP_VN_CO[0]));
    if (aqiCo > aqiMax) aqiMax = aqiCo;
  }

  if (aqiMax > 500) aqiMax = 500;
  return aqiMax;
}

// Đọc tất cả cảm biến rồi đánh giá ngưỡng. Không in, không điều khiển chân.
void sampleSensors() {
  r.tempC    = dht.readTemperature();
  r.humidity = dht.readHumidity();
  r.envOk    = !isnan(r.tempC) && !isnan(r.humidity);

  r.dustOk = readSDS(r.pm25, r.pm10);

  for (MqSensor &s : mqs) {
    s.mq->update();
    s.ppm = s.mq->readSensor();   // âm = lần đọc lỗi
    s.adc = analogRead(s.pin);
  }

  r.danger = (mqs[MQ_CO2].ppm >= mqs[MQ_CO2].thr) ||
             (mqs[MQ_LPG].ppm >= mqs[MQ_LPG].thr) ||
             (mqs[MQ_CO].ppm  >= mqs[MQ_CO].thr)  ||
             (r.dustOk && r.pm25 >= thrPm25);

  bool warning = (mqs[MQ_CO2].ppm >= mqs[MQ_CO2].thr * 0.8f) ||
                 (mqs[MQ_LPG].ppm >= mqs[MQ_LPG].thr * 0.8f) ||
                 (mqs[MQ_CO].ppm  >= mqs[MQ_CO].thr * 0.8f)  ||
                 (r.dustOk && r.pm25 >= thrPm25 * 0.8f);

  if (r.danger) {
    r.alertLevel = ALERT_DANGER;
  } else if (warning) {
    r.alertLevel = ALERT_WARNING;
  } else {
    r.alertLevel = ALERT_SAFE;
  }

  r.aqi = computeVnAqi(r.dustOk, r.pm25, r.pm10, mqs[MQ_CO].ppm);
}

// Hiệu chuẩn R0 đồng thời cả 3 cảm biến MQ trong không khí sạch
bool calibrateAllMqSensors(int samples) {
  if (samples < 1) samples = 10;
  if (samples > 30) samples = 30;

  Serial.println("\n==========================================");
  Serial.println("  BAT DAU HIEU CHUAN R0 CHO 3 CAM BIEN MQ ");
  Serial.println("==========================================");
  Serial.printf("So mau: %d | Luu y: Dat mach trong khong khi sach!\n", samples);

  float totals[MQ_COUNT] = {0};

  for (int i = 1; i <= samples; i++) {
    for (int idx = 0; idx < MQ_COUNT; idx++) {
      mqs[idx].mq->update();
      float c = mqs[idx].mq->calibrate(mqs[idx].cleanAirRatio);
      totals[idx] += c;
    }
    Serial.printf("  Dang lay mau: %d/%d\n", i, samples);
    delay(500);
  }

  Serial.println("\n----------- KET QUA HIEU CHUAN -----------");
  for (int idx = 0; idx < MQ_COUNT; idx++) {
    float newR0 = totals[idx] / samples;
    if (newR0 > 0 && !isnan(newR0) && !isinf(newR0)) {
      mqs[idx].r0 = newR0;
      mqs[idx].mq->setR0(newR0);
      Serial.printf("  %-10s R0 moi: %6.2f\n", mqs[idx].type, newR0);
    } else {
      Serial.printf("  %-10s Loi tinh toan R0!\n", mqs[idx].type);
    }
  }
  Serial.println("==========================================\n");
  return true;
}

// Trỏ tới ô ngưỡng theo key, hoặc nullptr nếu key không hợp lệ.
float *thresholdSlot(const String &key) {
  for (MqSensor &s : mqs) {
    if (key == s.key) return &s.thr;
  }
  if (key == "co2")    return &mqs[MQ_CO2].thr;
  if (key == "lpg")    return &mqs[MQ_LPG].thr;
  if (key == "co")     return &mqs[MQ_CO].thr;
  if (key == "pm2_5")  return &thrPm25;
  if (key == "pm10")   return &thrPm10;
  return nullptr;
}
