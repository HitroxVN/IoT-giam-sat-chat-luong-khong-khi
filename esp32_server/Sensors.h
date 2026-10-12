#pragma once

#include <Arduino.h>
#include <DHT.h>
#include <MQUnifiedsensor.h>
#include "Config.h"
#include "Types.h"

// Biến trạng thái đọc cảm biến toàn cục
extern Reading r;
extern MqSensor mqs[MQ_COUNT];
extern float thrPm25;
extern float thrPm10;

// Các hàm quản lý cảm biến
void setupSensors();
bool readSDS(float &pm25, float &pm10);
void sampleSensors();
bool calibrateAllMqSensors(int samples = 10);
float *thresholdSlot(const String &key);
int computeVnAqi(bool dustOk, float pm25, float pm10, float co_ppm);
