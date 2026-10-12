#pragma once

#include <Arduino.h>
#include <WebServer.h>

// Khởi tạo và xử lý các route REST API
void setupRoutes();
void handleServerClient();
void sendJson(int code, const String &body);
void sendData();
