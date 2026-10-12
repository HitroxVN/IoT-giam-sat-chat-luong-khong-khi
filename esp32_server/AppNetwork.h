#pragma once

#include <Arduino.h>
#include <WiFi.h>
#include <Firebase.h>
#include "Config.h"

// Trạng thái đồng bộ Firebase
extern bool firebaseEnabled;
extern int  fbLastCode;

// Quản lý WiFi & Firebase
void connectWiFi();
bool isWiFiConnected();
void sendToFirebase();
void sendThresholdsToFirebase();
void syncThresholdsFromFirebase();

// Tạo chuỗi JSON dữ liệu
void buildJson(char *buf, size_t n, bool wifi);
const char *boolStr(bool b);
