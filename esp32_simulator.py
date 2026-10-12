#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
=============================================================================
ESP32 AIR QUALITY MONITOR - PYTHON SIMULATOR
=============================================================================
Dựa trên source code gốc: main/main.ino
Mục đích:
  - Giả lập hoàn toàn vi điều khiển ESP32 và toàn bộ cảm biến ngoại vi:
      * DHT22 (Nhiệt độ & Độ ẩm)
      * SDS011 (Bụi mịn PM2.5 & PM10 qua UART)
      * MQ-135 (Khí CO2, đường đặc tuyến luỹ thừa + ADC 12-bit)
      * MQ-2   (Khí LPG, đường đặc tuyến luỹ thừa + ADC 12-bit)
      * MQ-7   (Khí CO, đường đặc tuyến luỹ thừa + ADC 12-bit)
      * LED & Buzzer (Chế độ auto theo cảnh báo hoặc bật/tắt thủ công)
  - Đồng bộ Firebase Realtime Database (LOCKED MODE có xác thực Token).
  - Cung cấp đầy đủ REST API chuẩn xác với mã phản hồi HTTP, CORS và JSON schema.
  - Mô phỏng chu kỳ đọc cảm biến (3s) và chu kỳ Firebase (30s).
  - Xuất log ra Console y hệt như Serial Monitor 115200 baud của ESP32.
  - Hỗ trợ CLI tương tác trực tiếp để mô phỏng sự cố: rò rỉ gas, khói bụi, lỗi cảm biến.
=============================================================================
"""

import sys
import time
import math
import random
import threading
import argparse
import json
import socket
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import urllib.request
import urllib.error

# ==========================================================
# 1. CẤU HÌNH HỆ THỐNG (Khớp 100% với main.ino)
# ==========================================================

WIFI_SSID = "HUNRE NOI BO 3"
WIFI_RSSI = -58

# Firebase (LOCKED MODE)
FB_URL = "https://your-project-id.firebasedatabase.app"
FB_TOKEN = "Your_Firebase_Database_Secret"
FB_PATH_LATEST = "esp32/latest"
FB_PATH_HISTORY = "esp32/history"
FB_PATH_THRESHOLDS = "esp32/thresholds"
FB_SEND_INTERVAL_SEC = 30.0  # 30 giây

# Chu kỳ đọc cảm biến
SENSOR_INTERVAL_SEC = 3.0  # 3 giây

# Cấu hình ADC & MQ
BOARD_TYPE = "ESP-32"
VOLTAGE_RESOLUTION = 3.3
ADC_BIT_RESOLUTION = 12
ADC_MAX = 4095

# Hệ số hiệu chuẩn & ngưỡng mặc định từ main.ino
MQ_CONFIGS = {
    "mq135": {
        "key": "mq135",
        "type": "MQ-135",
        "gas": "CO2",
        "pin": 32,
        "a": 110.47,
        "b": -2.862,
        "r0": 181.41,
        "clean_air_ratio": 0.638,
        "thr": 1500.0,
        "default_ppm": 650.0,
        "default_adc": 2130,
    },
    "mq2": {
        "key": "mq2",
        "type": "MQ-2",
        "gas": "LPG",
        "pin": 35,
        "a": 574.25,
        "b": -2.222,
        "r0": 14.45,
        "clean_air_ratio": 9.83,
        "thr": 400.0,
        "default_ppm": 7.0,
        "default_adc": 2380,
    },
    "mq7": {
        "key": "mq7",
        "type": "MQ-7",
        "gas": "CO",
        "pin": 34,
        "a": 99.04,
        "b": -1.518,
        "r0": 3.32,
        "clean_air_ratio": 27.5,
        "thr": 50.0,
        "default_ppm": 4.0,
        "default_adc": 3150,
    },
}

# Ngưỡng bụi mịn mặc định
DEFAULT_THR_PM25 = 50.0
DEFAULT_THR_PM10 = 100.0

# ==========================================================
# BẢNG TÍNH CHỈ SỐ VN_AQI (Quyết định số 1459/QĐ-TCMT)
# ==========================================================
BP_VN_PM25 = [
    (0, 50, 0.0, 25.0),
    (51, 100, 25.1, 50.0),
    (101, 150, 50.1, 80.0),
    (151, 200, 80.1, 150.0),
    (201, 300, 150.1, 250.0),
    (301, 400, 250.1, 350.0),
    (401, 500, 350.1, 500.0),
]

BP_VN_PM10 = [
    (0, 50, 0.0, 50.0),
    (51, 100, 50.1, 150.0),
    (101, 150, 150.1, 250.0),
    (151, 200, 250.1, 350.0),
    (201, 300, 350.1, 420.0),
    (301, 400, 420.1, 500.0),
    (401, 500, 500.1, 600.0),
]

BP_VN_CO = [
    (0, 50, 0.0, 10000.0),
    (51, 100, 10001.0, 30000.0),
    (101, 150, 30001.0, 45000.0),
    (151, 200, 45001.0, 60000.0),
    (201, 300, 60001.0, 90000.0),
    (301, 400, 90001.0, 120000.0),
    (401, 500, 120001.0, 150000.0),
]

def calc_single_vn_aqi(c, bps):
    if c <= 0.0:
        return 0
    for i_lo, i_hi, bp_lo, bp_hi in bps:
        if c <= bp_hi:
            span = bp_hi - bp_lo
            if span <= 0:
                return i_lo
            return int(round(((i_hi - i_lo) / span) * (c - bp_lo) + i_lo))
    return 500

def compute_vn_aqi(dust_ok, pm25, pm10, co_ppm):
    if not dust_ok or (pm25 < 0 and pm10 < 0):
        return -1, "Chưa có"
    aqi_max = 0
    if pm25 >= 0:
        aqi_max = max(aqi_max, calc_single_vn_aqi(pm25, BP_VN_PM25))
    if pm10 >= 0:
        aqi_max = max(aqi_max, calc_single_vn_aqi(pm10, BP_VN_PM10))
    if co_ppm > 0:
        aqi_max = max(aqi_max, calc_single_vn_aqi(co_ppm * 1145.0, BP_VN_CO))
    aqi_max = min(500, aqi_max)
    cat = "Tốt" if aqi_max <= 50 else ("Trung bình" if aqi_max <= 100 else ("Kém" if aqi_max <= 150 else ("Xấu" if aqi_max <= 200 else ("Rất xấu" if aqi_max <= 300 else "Nguy hại"))))
    return aqi_max, cat


# ==========================================================
# 2. TRẠNG THÁI HỆ THỐNG ESP32
# ==========================================================

class ESP32State:
    def __init__(self):
        self.lock = threading.RLock()
        self.start_time = time.time()

        # Cảm biến môi trường DHT22
        self.temp_c = 29.40
        self.humidity = 68.20
        self.env_ok = True

        # Cảm biến bụi SDS011
        self.pm25 = 25.0
        self.pm10 = 45.0
        self.dust_ok = True

        # Cảm biến khí MQ
        self.mqs = {}
        for k, cfg in MQ_CONFIGS.items():
            self.mqs[k] = {
                "key": cfg["key"],
                "type": cfg["type"],
                "gas": cfg["gas"],
                "pin": cfg["pin"],
                "a": cfg["a"],
                "b": cfg["b"],
                "r0": cfg["r0"],
                "clean_air_ratio": cfg["clean_air_ratio"],
                "thr": float(cfg["thr"]),
                "ppm": float(cfg["default_ppm"]),
                "adc": int(cfg["default_adc"]),
            }

        # Ngưỡng bụi
        self.thr_pm25 = DEFAULT_THR_PM25
        self.thr_pm10 = DEFAULT_THR_PM10

        # Cờ và cấp độ cảnh báo
        self.danger = False
        self.alert_level = "safe"
        self.aqi = -1
        self.aqi_cat = "Chưa có"

        # Cơ cấu chấp hành (-1 = auto, 0 = off, 1 = on)
        self.led_mode = -1
        self.buzzer_mode = -1
        self.fan_mode = -1
        self.led_pin = 0
        self.buzzer_pin = 0
        self.fan_pin = 0

        # Firebase
        self.firebase_enabled = True
        self.fb_last_code = 0
        self.last_fb_send = 0

        # Chế độ mô phỏng
        self.noise_enabled = True
        self.override_active = False

        self.evaluate_danger()

    @property
    def uptime_ms(self):
        return int((time.time() - self.start_time) * 1000)

    def evaluate_danger(self):
        with self.lock:
            # Ngưỡng kích hoạt cảnh báo khớp logic main.ino
            self.danger = (
                self.mqs["mq135"]["ppm"] >= self.mqs["mq135"]["thr"] or
                self.mqs["mq2"]["ppm"] >= self.mqs["mq2"]["thr"] or
                self.mqs["mq7"]["ppm"] >= self.mqs["mq7"]["thr"] or
                (self.dust_ok and self.pm25 >= self.thr_pm25)
            )
            warning = (
                self.mqs["mq135"]["ppm"] >= self.mqs["mq135"]["thr"] * 0.8 or
                self.mqs["mq2"]["ppm"] >= self.mqs["mq2"]["thr"] * 0.8 or
                self.mqs["mq7"]["ppm"] >= self.mqs["mq7"]["thr"] * 0.8 or
                (self.dust_ok and self.pm25 >= self.thr_pm25 * 0.8)
            )
            if self.danger:
                self.alert_level = "danger"
            elif warning:
                self.alert_level = "warning"
            else:
                self.alert_level = "safe"

            # Cập nhật chân LED, Buzzer & Quạt
            # Ở chế độ auto: LED bật khi warning hoặc danger; Buzzer & Fan chỉ kích hoạt khi danger
            self.led_pin = (1 if self.alert_level != "safe" else 0) if self.led_mode < 0 else self.led_mode
            self.buzzer_pin = (1 if self.alert_level == "danger" else 0) if self.buzzer_mode < 0 else self.buzzer_mode
            self.fan_pin = (1 if self.alert_level == "danger" else 0) if self.fan_mode < 0 else self.fan_mode

            self.aqi, self.aqi_cat = compute_vn_aqi(self.dust_ok, self.pm25, self.pm10, self.mqs["mq7"]["ppm"])

    def sample_sensors(self):
        """Mô phỏng chu kỳ đọc cảm biến với dao động vật lý tự nhiên."""
        with self.lock:
            if not self.override_active and self.noise_enabled:
                if self.env_ok:
                    self.temp_c = max(15.0, min(45.0, self.temp_c + random.uniform(-0.15, 0.15)))
                    self.humidity = max(30.0, min(95.0, self.humidity + random.uniform(-0.3, 0.3)))

                if self.dust_ok:
                    self.pm25 = max(5.0, min(300.0, self.pm25 + random.uniform(-1.2, 1.2)))
                    self.pm10 = max(self.pm25, min(500.0, self.pm25 * random.uniform(1.4, 1.8)))

                # Khí MQ
                for k, m in self.mqs.items():
                    fluct = random.uniform(-0.015, 0.015)
                    m["ppm"] = max(1.0, m["ppm"] * (1.0 + fluct))
                    # Biến thiên ADC nhẹ
                    m["adc"] = max(0, min(ADC_MAX, int(m["adc"] + random.randint(-8, 8))))

            self.evaluate_danger()

    def calibrate(self):
        """Hiệu chuẩn R0 đồng thời cho cả 3 cảm biến MQ trong không khí sạch."""
        with self.lock:
            results = []
            for k in ["mq135", "mq2", "mq7"]:
                base_r0 = MQ_CONFIGS[k]["r0"]
                new_r0 = round(base_r0 * random.uniform(0.98, 1.02), 2)
                self.mqs[k]["r0"] = new_r0
                results.append({
                    "key": self.mqs[k]["key"],
                    "gas": self.mqs[k]["gas"],
                    "r0": new_r0,
                    "clean_air_ratio": self.mqs[k]["clean_air_ratio"]
                })
            return results

    def build_json(self):
        """Khớp chính xác với hàm buildJson() trong main.ino."""
        with self.lock:
            return {
                "device": "esp32-air-quality",
                "uptime_ms": self.uptime_ms,
                "wifi": {
                    "connected": True,
                    "ssid": WIFI_SSID,
                    "rssi": WIFI_RSSI
                },
                "env": {
                    "valid": self.env_ok,
                    "temp_c": round(self.temp_c, 2) if self.env_ok else 0.0,
                    "humidity": round(self.humidity, 2) if self.env_ok else 0.0
                },
                "dust": {
                    "valid": self.dust_ok,
                    "pm2_5": round(self.pm25, 1),
                    "pm10": round(self.pm10, 1)
                },
                "gas": {
                    "co2_ppm": round(self.mqs["mq135"]["ppm"], 1),
                    "lpg_ppm": round(self.mqs["mq2"]["ppm"], 1),
                    "co_ppm": round(self.mqs["mq7"]["ppm"], 1)
                },
                "aqi": {
                    "value": self.aqi,
                    "category": self.aqi_cat
                },
                "alert": {
                    "level": self.alert_level,
                    "danger": self.danger,
                    "led": self.led_pin,
                    "buzzer": self.buzzer_pin,
                    "fan": self.fan_pin
                },
                "firebase": {
                    "enabled": self.firebase_enabled,
                    "last_code": self.fb_last_code,
                    "interval_ms": int(FB_SEND_INTERVAL_SEC * 1000)
                },
                "thresholds": {
                    "co2": round(self.mqs["mq135"]["thr"]),
                    "lpg": round(self.mqs["mq2"]["thr"]),
                    "co": round(self.mqs["mq7"]["thr"]),
                    "pm2_5": round(self.thr_pm25),
                    "pm10": round(self.thr_pm10)
                }
            }

    def build_mq_list(self):
        """Khớp chính xác với handleMqList() trong main.ino."""
        with self.lock:
            order = ["mq135", "mq2", "mq7"]
            sensors = []
            for k in order:
                s = self.mqs[k]
                sensors.append({
                    "key": s["key"],
                    "gas": s["gas"],
                    "ppm": round(s["ppm"], 1),
                    "adc": s["adc"],
                    "r0": s["r0"],
                    "a": s["a"],
                    "b": s["b"],
                    "valid": s["ppm"] >= 0
                })
            return {"sensors": sensors}

    def build_mq_single(self, key):
        """Khớp chính xác với sendMq() trong main.ino."""
        with self.lock:
            if key not in self.mqs:
                return None
            s = self.mqs[key]
            return {
                "key": s["key"],
                "gas": s["gas"],
                "ppm": round(s["ppm"], 1),
                "adc": s["adc"],
                "r0": s["r0"],
                "a": s["a"],
                "b": s["b"],
                "valid": s["ppm"] >= 0
            }


esp = ESP32State()


# ==========================================================
# 3. ĐỒNG BỘ FIREBASE
# ==========================================================

def send_to_firebase_sync():
    """Gửi dữ liệu lên Firebase Realtime Database (LOCKED mode token)."""
    if not esp.firebase_enabled:
        return

    data = esp.build_json()
    json_bytes = json.dumps(data).encode("utf-8")

    # 1. Ghi đè esp32/latest
    latest_url = f"{FB_URL}/{FB_PATH_LATEST}.json?auth={FB_TOKEN}"
    history_url = f"{FB_URL}/{FB_PATH_HISTORY}.json?auth={FB_TOKEN}"

    code = 0
    try:
        req_latest = urllib.request.Request(
            latest_url,
            data=json_bytes,
            headers={"Content-Type": "application/json"},
            method="PUT"
        )
        with urllib.request.urlopen(req_latest, timeout=6) as resp:
            code = resp.status
        print(f"[FB] latest -> {code}")
    except urllib.error.HTTPError as e:
        code = e.code
        print(f"[FB] latest -> {code}")
    except Exception as e:
        print(f"[FB] latest loi ket noi: {e}")
        code = 0

    esp.fb_last_code = code

    # 2. Push vào esp32/history
    try:
        req_hist = urllib.request.Request(
            history_url,
            data=json_bytes,
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        with urllib.request.urlopen(req_hist, timeout=6) as resp:
            hcode = resp.status
            if hcode != 200:
                print(f"[FB] history -> {hcode}")
    except Exception as e:
        pass


def send_thresholds_to_firebase():
    """Gửi các ngưỡng cảnh báo lên Firebase Realtime Database."""
    if not esp.firebase_enabled:
        return
    with esp.lock:
        thr_data = {
            "co2": round(esp.mqs["mq135"]["thr"]),
            "lpg": round(esp.mqs["mq2"]["thr"]),
            "co": round(esp.mqs["mq7"]["thr"]),
            "pm2_5": round(esp.thr_pm25),
            "pm10": round(esp.thr_pm10)
        }
    json_bytes = json.dumps(thr_data).encode("utf-8")
    url = f"{FB_URL}/{FB_PATH_THRESHOLDS}.json?auth={FB_TOKEN}"
    try:
        req = urllib.request.Request(
            url,
            data=json_bytes,
            headers={"Content-Type": "application/json"},
            method="PUT"
        )
        with urllib.request.urlopen(req, timeout=6) as resp:
            code = resp.status
        print(f"[FB] thresholds -> {code}")
    except urllib.error.HTTPError as e:
        print(f"[FB] thresholds -> {e.code}")
    except Exception as e:
        print(f"[FB] thresholds loi ket noi: {e}")


def sync_thresholds_from_firebase():
    """Lấy ngưỡng cài đặt từ Firebase Realtime Database khi khởi động."""
    if not esp.firebase_enabled:
        return
    url = f"{FB_URL}/{FB_PATH_THRESHOLDS}.json?auth={FB_TOKEN}"
    print(f"[FB] Dang kiem tra nguong tu Firebase ({FB_PATH_THRESHOLDS}) ...")
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=6) as resp:
            body = resp.read().decode("utf-8").strip()
            if resp.status == 200 and body and body != "null":
                data = json.loads(body)
                updated = False
                with esp.lock:
                    if "co2" in data and float(data["co2"]) > 0:
                        esp.mqs["mq135"]["thr"] = float(data["co2"])
                        updated = True
                    if "lpg" in data and float(data["lpg"]) > 0:
                        esp.mqs["mq2"]["thr"] = float(data["lpg"])
                        updated = True
                    if "co" in data and float(data["co"]) > 0:
                        esp.mqs["mq7"]["thr"] = float(data["co"])
                        updated = True
                    if "pm2_5" in data and float(data["pm2_5"]) > 0:
                        esp.thr_pm25 = float(data["pm2_5"])
                        updated = True
                    if "pm10" in data and float(data["pm10"]) > 0:
                        esp.thr_pm10 = float(data["pm10"])
                        updated = True
                    esp.evaluate_danger()
                if updated:
                    print(f"[FB] Da dong bo nguong tu Firebase: CO2={esp.mqs['mq135']['thr']}, LPG={esp.mqs['mq2']['thr']}, CO={esp.mqs['mq7']['thr']}, PM2.5={esp.thr_pm25}, PM10={esp.thr_pm10}")
            else:
                print("[FB] Chua co nguong tren Firebase, dang day nguong mac dinh len...")
                send_thresholds_to_firebase()
    except Exception as e:
        print(f"[FB] Khong the dong bo nguong tu Firebase: {e}")


# ==========================================================
# 4. IN BÁO CÁO SERIAL (Khớp 100% với printReport() trong main.ino)
# ==========================================================

def print_serial_report():
    with esp.lock:
        print("\n------------------------------------------")
        print("[ MOI TRUONG - DHT22 ]")
        if esp.env_ok:
            print(f"  {'Nhiet do:':<18} {esp.temp_c:6.1f} *C")
            print(f"  {'Do am:':<18} {esp.humidity:6.1f} %")
        else:
            print("  Loi: Khong doc duoc DHT22")

        print("[ BUI MIN - SDS011 ]")
        if esp.dust_ok:
            print(f"  {'PM2.5:':<18} {esp.pm25:6.1f} ug/m3")
            print(f"  {'PM10:':<18} {esp.pm10:6.1f} ug/m3")
            if esp.aqi >= 0:
                print(f"  {'VN_AQI:':<18} {esp.aqi} ({esp.aqi_cat})")
        else:
            print("  Dang doi frame du lieu SDS011...")

        print("[ KHI DOC & O NHIEM - MQ ]")
        for k in ["mq135", "mq2", "mq7"]:
            s = esp.mqs[k]
            if s["ppm"] < 0:
                print(f"  {s['type'] + ':':<18} loi doc")
            else:
                print(f"  {s['type'] + ':':<18} {s['ppm']:6.1f} ppm   (ADC {s['adc']})")

        print("[ TRANG THAI CANH BAO ]")
        if esp.alert_level == "danger":
            print("  [DANGER - NGUY HIEM] Chi so vuot nguong an toan!")
        elif esp.alert_level == "warning":
            print("  [WARNING - CANH BAO] Chi so tiem can nguong (>= 80%)!")
        else:
            print("  [SAFE - AN TOAN] Cac chi so trong muc binh thuong")
        print(f"  LED: {'ON' if esp.led_pin else 'OFF'} | Buzzer: {'ON' if esp.buzzer_pin else 'OFF'} | Quat (D18): {'ON' if esp.fan_pin else 'OFF'}")
        print("------------------------------------------")


# ==========================================================
# 5. HTTP SERVER REST API
# ==========================================================

def parse_state_arg(val):
    """
    Phân tích giá trị state giống hàm parseState() trong main.ino:
    -1 = auto, 1 = on/true/1, 0 = off/false/0, -2 = lỗi
    """
    if val is None:
        return -2
    val = str(val).strip().lower()
    if val == "auto":
        return -1
    if val in ("1", "on", "true"):
        return 1
    if val in ("0", "off", "false"):
        return 0
    return -2


class ESP32HttpHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Ẩn log truy cập http mặc định để không làm loãng Serial Monitor
        pass

    def send_cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Origin")

    def send_json(self, status_code, data):
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_cors_headers()
        self.end_headers()
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_cors_headers()
        self.end_headers()

    def get_params(self):
        """Lấy tham số từ Query String và Form/JSON Body."""
        parsed = urlparse(self.path)
        params = {}
        for k, v in parse_qs(parsed.query).items():
            params[k] = v[0] if v else ""

        length = int(self.headers.get("Content-Length", 0))
        if length > 0:
            raw_body = self.rfile.read(length).decode("utf-8", errors="ignore")
            # Thử parse JSON
            try:
                body_json = json.loads(raw_body)
                if isinstance(body_json, dict):
                    for k, v in body_json.items():
                        params[k] = str(v)
            except Exception:
                # Thử parse URL-encoded form
                for k, v in parse_qs(raw_body).items():
                    params[k] = v[0] if v else ""
                # plain text
                if "state" not in params and raw_body.strip():
                    params["plain"] = raw_body.strip()
        return parsed.path, params

    def do_GET(self):
        path, params = self.get_params()

        # 1. GET /api/data
        if path == "/api/data":
            self.send_json(200, esp.build_json())
            return

        # 2. GET /api/mq
        if path == "/api/mq":
            self.send_json(200, esp.build_mq_list())
            return

        # 3. GET /api/mq/<key>
        if path.startswith("/api/mq/"):
            key = path[len("/api/mq/"):].strip()
            sensor = esp.build_mq_single(key)
            if sensor:
                self.send_json(200, sensor)
            else:
                self.send_json(404, {"error": "Khong co cam bien nay"})
            return

        # 4. GET /api/firebase
        if path == "/api/firebase":
            self.send_json(200, esp.build_json())
            return

        # 5. GET /api/sensors (Legacy compatibility)
        if path == "/api/sensors":
            d = esp.build_json()
            legacy = {
                "temperature": d["env"]["temp_c"],
                "humidity": d["env"]["humidity"],
                "mq135": int(d["gas"]["co2_ppm"]),
                "threshold": int(d["thresholds"]["co2"]),
                "air_quality": "bad" if d["alert"]["danger"] else "good",
                "alert": d["alert"]["danger"],
                "led": bool(d["alert"]["led"]),
                "buzzer": bool(d["alert"]["buzzer"]),
                "dht_ok": d["env"]["valid"],
                "valid": True
            }
            self.send_json(200, legacy)
            return

        # 6. GET /api/calibrate
        if path == "/api/calibrate":
            sensors = [
                {
                    "key": s["key"],
                    "gas": s["gas"],
                    "r0": s["r0"],
                    "clean_air_ratio": s["clean_air_ratio"]
                }
                for s in esp.mqs.values()
            ]
            self.send_json(200, {"sensors": sensors})
            return

        # 7. Tự động phục vụ dashboard.html nếu người dùng mở từ trình duyệt
        if path in ("/", "/dashboard", "/dashboard.html", "/index.html"):
            try:
                target_file = "dashboard.html" if path != "/index.html" else "index.html"
                with open(target_file, "rb") as f:
                    content = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_cors_headers()
                self.end_headers()
                self.wfile.write(content)
                return
            except Exception:
                pass

        # 7. Endpoint không tồn tại -> 404
        self.send_json(404, {"error": "Khong tim thay endpoint"})

    def do_POST(self):
        path, params = self.get_params()

        # 1. POST /api/led
        if path == "/api/led":
            state_val = params.get("state") or params.get("plain")
            mode = parse_state_arg(state_val)
            if mode == -2:
                self.send_json(400, {"error": "Thieu state hoac sai gia tri. Dung ?state=on|off|auto"})
                return
            with esp.lock:
                esp.led_mode = mode
                esp.evaluate_danger()
            mode_str = "auto" if mode < 0 else ("bat" if mode else "tat")
            print(f"[API] LED -> {mode_str}")
            self.send_json(200, esp.build_json())
            return

        # 2. POST /api/buzzer
        if path == "/api/buzzer":
            state_val = params.get("state") or params.get("plain")
            mode = parse_state_arg(state_val)
            if mode == -2:
                self.send_json(400, {"error": "Thieu state hoac sai gia tri. Dung ?state=on|off|auto"})
                return
            with esp.lock:
                esp.buzzer_mode = mode
                esp.evaluate_danger()
            mode_str = "auto" if mode < 0 else ("bat" if mode else "tat")
            print(f"[API] Buzzer -> {mode_str}")
            self.send_json(200, esp.build_json())
            return

        # 3. POST /api/fan
        if path == "/api/fan":
            state_val = params.get("state") or params.get("plain")
            mode = parse_state_arg(state_val)
            if mode == -2:
                self.send_json(400, {"error": "Thieu state hoac sai gia tri. Dung ?state=on|off|auto"})
                return
            with esp.lock:
                esp.fan_mode = mode
                esp.evaluate_danger()
            mode_str = "auto" if mode < 0 else ("bat" if mode else "tat")
            print(f"[API] Fan -> {mode_str}")
            self.send_json(200, esp.build_json())
            return

        # 4. POST /api/firebase
        if path == "/api/firebase":
            state_val = params.get("state") or params.get("plain")
            mode = parse_state_arg(state_val)
            if mode not in (0, 1):
                self.send_json(400, {"error": "Chi nhan on|off|1|0|true|false"})
                return
            with esp.lock:
                esp.firebase_enabled = (mode == 1)
            if esp.firebase_enabled:
                print("[FB] Bat dong bo")
                threading.Thread(target=send_to_firebase_sync, daemon=True).start()
            else:
                print("[FB] Tat dong bo")
            self.send_json(200, esp.build_json())
            return

        # 4. POST /api/threshold
        if path == "/api/threshold":
            key = params.get("key")
            value = params.get("value")

            if not key or value is None:
                self.send_json(400, {"error": "Can co key va value"})
                return

            key = key.strip().lower()
            val_str = str(value).strip()

            if not val_str:
                self.send_json(400, {"error": "value rong"})
                return

            try:
                v = float(val_str)
                if v <= 0:
                    self.send_json(400, {"error": "value phai la so > 0"})
                    return
            except ValueError:
                self.send_json(400, {"error": "value phai la so > 0"})
                return

            # Hỗ trợ cả key trong main.ino và alias trong API.md
            with esp.lock:
                if key in ("mq135", "co2"):
                    esp.mqs["mq135"]["thr"] = v
                elif key in ("mq2", "lpg"):
                    esp.mqs["mq2"]["thr"] = v
                elif key in ("mq7", "co"):
                    esp.mqs["mq7"]["thr"] = v
                elif key == "pm2_5":
                    esp.thr_pm25 = v
                elif key == "pm10":
                    esp.thr_pm10 = v
                else:
                    self.send_json(404, {"error": "Khong co chi so nay. Dung: mq135, mq2, mq7, pm2_5, pm10"})
                    return

                esp.evaluate_danger()

            print(f"[API] Nguong {key} -> {v:.1f}")
            threading.Thread(target=send_thresholds_to_firebase, daemon=True).start()
            self.send_json(200, esp.build_json())
            return

        # 5. POST /api/simulate (Endpoint mở rộng cho mô phỏng trực tiếp từ API/Web)
        if path == "/api/simulate":
            with esp.lock:
                scenario = params.get("scenario")
                if scenario == "danger" or scenario == "smoke":
                    esp.mqs["mq135"]["ppm"] = 1800.0
                    esp.pm25 = 85.0
                    esp.pm10 = 140.0
                    esp.override_active = True
                elif scenario == "gas":
                    esp.mqs["mq2"]["ppm"] = 520.0
                    esp.override_active = True
                elif scenario == "normal":
                    esp.mqs["mq135"]["ppm"] = 650.0
                    esp.mqs["mq2"]["ppm"] = 7.0
                    esp.mqs["mq7"]["ppm"] = 4.0
                    esp.pm25 = 25.0
                    esp.pm10 = 45.0
                    esp.env_ok = True
                    esp.dust_ok = True
                    esp.override_active = False
                elif scenario == "error":
                    esp.env_ok = False
                    esp.dust_ok = False
                    esp.override_active = True

                if "co2" in params:
                    esp.mqs["mq135"]["ppm"] = float(params["co2"])
                    esp.override_active = True
                if "lpg" in params:
                    esp.mqs["mq2"]["ppm"] = float(params["lpg"])
                    esp.override_active = True
                if "co" in params:
                    esp.mqs["mq7"]["ppm"] = float(params["co"])
                    esp.override_active = True
                if "pm25" in params:
                    esp.pm25 = float(params["pm25"])
                    esp.override_active = True
                if "temp" in params:
                    esp.temp_c = float(params["temp"])
                if "humidity" in params:
                    esp.humidity = float(params["humidity"])

                esp.evaluate_danger()

            self.send_json(200, esp.build_json())
            return

        # 6. POST /api/calibrate
        if path == "/api/calibrate":
            results = esp.calibrate()
            print(f"[API] Hieu chuan R0 ca 3 cam bien thanh cong: {results}")
            self.send_json(200, {
                "success": True,
                "message": "Hieu chuan R0 ca 3 cam bien thanh cong",
                "sensors": results
            })
            return

        # Fallback 404
        self.send_json(404, {"error": "Khong tim thay endpoint"})


# ==========================================================
# 6. VÒNG LẶP NỀN (Khớp hàm loop() trong main.ino)
# ==========================================================

def background_loop():
    last_sensor_time = 0.0
    last_fb_time = 0.0

    # Đồng bộ ngưỡng cài đặt từ Firebase khi khởi động
    sync_thresholds_from_firebase()

    # Lấy mẫu đầu tiên ngay khi khởi động
    esp.sample_sensors()
    print_serial_report()
    threading.Thread(target=send_to_firebase_sync, daemon=True).start()

    while True:
        now = time.time()

        # Chu kỳ đọc cảm biến & in báo cáo Serial (3s)
        if now - last_sensor_time >= SENSOR_INTERVAL_SEC:
            last_sensor_time = now
            esp.sample_sensors()
            print_serial_report()

        # Chu kỳ gửi Firebase (30s)
        if now - last_fb_time >= FB_SEND_INTERVAL_SEC:
            last_fb_time = now
            threading.Thread(target=send_to_firebase_sync, daemon=True).start()

        time.sleep(0.1)


# ==========================================================
# 7. GIAO DIỆN DÒNG LỆNH TƯƠNG TÁC (CLI)
# ==========================================================

def print_help():
    print("""
=============================================================
  CÁC LỆNH TƯƠNG TÁC GIẢ LẬP ESP32:
=============================================================
  danger / alert     : Kích hoạt tình trạng khẩn cấp (CO2 & PM2.5 cao)
  smoke              : Giả lập có khói / ô nhiễm nặng
  gas                : Giả lập rò rỉ khí gas LPG vượt ngưỡng
  normal / safe      : Đưa chỉ số về trạng thái bình thường (an toàn)
  error              : Giả lập cảm biến lỗi / ngắt kết nối
  status             : In trạng thái hiện tại của hệ thống
  set co2 <ppm>      : Đặt nồng độ CO2 (MQ-135)
  set lpg <ppm>      : Đặt nồng độ LPG (MQ-2)
  set co <ppm>       : Đặt nồng độ CO (MQ-7)
  set pm25 <ug/m3>   : Đặt chỉ số PM2.5
  set temp <c>       : Đặt nhiệt độ °C
  set hum <% >       : Đặt độ ẩm %
  led <on|off|auto>  : Điều khiển đèn LED
  buzzer <on|off|auto>: Điều khiển còi Buzzer
  fan <on|off|auto>  : Điều khiển quạt hút / thông gió (D18)
  calib / c          : Hiệu chuẩn lại R0 cho 3 cảm biến MQ trong không khí sạch
  help               : Xem lại danh sách lệnh này
  quit / exit        : Dừng server giả lập
=============================================================
""")


def cli_loop():
    time.sleep(1.0)
    print_help()
    while True:
        try:
            line = input().strip()
            if not line:
                continue
            parts = line.split()
            cmd = parts[0].lower()

            if cmd in ("exit", "quit"):
                print("\n[ESP32] Dang dung server...")
                sys.exit(0)

            elif cmd == "help":
                print_help()

            elif cmd in ("alert", "danger", "smoke"):
                with esp.lock:
                    esp.mqs["mq135"]["ppm"] = 1850.0
                    esp.pm25 = 85.0
                    esp.pm10 = 135.0
                    esp.override_active = True
                    esp.evaluate_danger()
                print("[SIM] -> Đã kích hoạt kịch bản NGUY HIỂM / KHÓI (Danger = True)")

            elif cmd == "gas":
                with esp.lock:
                    esp.mqs["mq2"]["ppm"] = 480.0
                    esp.override_active = True
                    esp.evaluate_danger()
                print("[SIM] -> Đã kích hoạt kịch bản RÒ RỈ KHÍ GAS LPG (Danger = True)")

            elif cmd in ("normal", "safe"):
                with esp.lock:
                    esp.mqs["mq135"]["ppm"] = 650.0
                    esp.mqs["mq2"]["ppm"] = 7.0
                    esp.mqs["mq7"]["ppm"] = 4.0
                    esp.pm25 = 24.5
                    esp.pm10 = 42.0
                    esp.env_ok = True
                    esp.dust_ok = True
                    esp.override_active = False
                    esp.evaluate_danger()
                print("[SIM] -> Đã phục hồi chỉ số KHÔNG KHÍ SẠCH BÌNH THƯỜNG")

            elif cmd == "error":
                with esp.lock:
                    esp.env_ok = False
                    esp.dust_ok = False
                    esp.override_active = True
                    esp.evaluate_danger()
                print("[SIM] -> Đã giả lập ngắt kết nối cảm biến DHT22 & SDS011")

            elif cmd == "status":
                print_serial_report()

            elif cmd in ("calib", "calibrate", "c"):
                print("\n==========================================")
                print("  BAT DAU HIEU CHUAN R0 CHO CAM BIEN MQ   ")
                print("==========================================")
                res = esp.calibrate()
                print("\n----------- KET QUA HIEU CHUAN -----------")
                for r in res:
                    print(f"  {r['gas']:<6} ({r['key']}) R0 moi: {r['r0']:.2f}")
                print("==========================================\n")

            elif cmd == "set" and len(parts) >= 3:
                key = parts[1].lower()
                try:
                    val = float(parts[2])
                    with esp.lock:
                        if key in ("co2", "mq135"):
                            esp.mqs["mq135"]["ppm"] = val
                        elif key in ("lpg", "mq2"):
                            esp.mqs["mq2"]["ppm"] = val
                        elif key in ("co", "mq7"):
                            esp.mqs["mq7"]["ppm"] = val
                        elif key in ("pm25", "pm2_5"):
                            esp.pm25 = val
                        elif key == "pm10":
                            esp.pm10 = val
                        elif key in ("temp", "nhietdo"):
                            esp.temp_c = val
                        elif key in ("hum", "doam"):
                            esp.humidity = val
                        else:
                            print(f"[SIM] Khong ro chi so '{key}'")
                            continue
                        esp.override_active = True
                        esp.evaluate_danger()
                    print(f"[SIM] -> Đặt {key} = {val}")
                except ValueError:
                    print("[SIM] Gia tri phai la mot so")

            elif cmd in ("thr", "threshold") and len(parts) >= 3:
                key = parts[1].lower()
                try:
                    val = float(parts[2])
                    if val > 0:
                        with esp.lock:
                            if key in ("co2", "mq135"):
                                esp.mqs["mq135"]["thr"] = val
                            elif key in ("lpg", "mq2"):
                                esp.mqs["mq2"]["thr"] = val
                            elif key in ("co", "mq7"):
                                esp.mqs["mq7"]["thr"] = val
                            elif key in ("pm25", "pm2_5"):
                                esp.thr_pm25 = val
                            elif key == "pm10":
                                esp.thr_pm10 = val
                            else:
                                print(f"[SIM] Khong ro chi so '{key}'. Dung: co2, lpg, co, pm2_5, pm10")
                                continue
                            esp.evaluate_danger()
                        threading.Thread(target=send_thresholds_to_firebase, daemon=True).start()
                        print(f"[SIM] -> Đặt ngưỡng {key} = {val} và đồng bộ Firebase")
                    else:
                        print("[SIM] Ngưỡng phải > 0")
                except ValueError:
                    print("[SIM] Gia tri phai la mot so")

            elif cmd == "led" and len(parts) >= 2:
                mode = parse_state_arg(parts[1])
                if mode != -2:
                    with esp.lock:
                        esp.led_mode = mode
                        esp.evaluate_danger()
                    print(f"[SIM] LED -> {parts[1]}")
                else:
                    print("[SIM] Dung: led on | off | auto")

            elif cmd == "buzzer" and len(parts) >= 2:
                mode = parse_state_arg(parts[1])
                if mode != -2:
                    with esp.lock:
                        esp.buzzer_mode = mode
                        esp.evaluate_danger()
                    print(f"[SIM] Buzzer -> {parts[1]}")
                else:
                    print("[SIM] Dung: buzzer on | off | auto")

            elif cmd == "fan" and len(parts) >= 2:
                mode = parse_state_arg(parts[1])
                if mode != -2:
                    with esp.lock:
                        esp.fan_mode = mode
                        esp.evaluate_danger()
                    print(f"[SIM] Fan -> {parts[1]}")
                else:
                    print("[SIM] Dung: fan on | off | auto")

            else:
                print(f"[SIM] Lenh '{line}' khong hop le. Go 'help' de xem huong dan.")

        except (EOFError, KeyboardInterrupt):
            break
        except Exception as e:
            print(f"[CLI Error]: {e}")


# ==========================================================
# 8. KHỞI ĐỘNG HỆ THỐNG
# ==========================================================

def get_lan_ip():
    """Lấy IP mạng LAN thực sự để các thiết bị khác trên mạng truy cập được."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(1)
        # Kết nối tới một địa chỉ ngoài mạng để lấy IP địịa phương
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


def print_banner(host, port):
    lan_ip = get_lan_ip()
    print("\n==========================================")
    print("  ESP32 AIR QUALITY MONITOR SYSTEM READY  ")
    print("==========================================")
    for k in ["mq135", "mq2", "mq7"]:
        s = esp.mqs[k]
        print(f"{s['key']:<6} pin {s['pin']:2d}  R0 {s['r0']:.2f}  a {s['a']:.3f}  b {s['b']:.3f}")
    print(f'[WiFi] Dang ket noi toi "{WIFI_SSID}" ...')
    print(f"[WiFi] OK - IP LAN: {lan_ip}")
    print(f"[HTTP] Server: http://{host}:{port}")
    print(f"[HTTP] Truy cap tu thiet bi khac tren mang LAN:")
    print(f"       http://{lan_ip}:{port}/api/data")
    print("==========================================")


def main():
    parser = argparse.ArgumentParser(description="ESP32 Air Quality Monitor Server Simulator")
    parser.add_argument("--host", default="0.0.0.0", help="Host bind address (mac dinh 0.0.0.0)")
    parser.add_argument("--port", type=int, default=80, help="Port HTTP server (mac dinh 80 nhu ESP32)")
    parser.add_argument("--no-cli", action="store_true", help="Tat giao dien CLI tuong tac")
    args = parser.parse_args()

    port = args.port
    server = None

    try:
        server = ThreadingHTTPServer((args.host, port), ESP32HttpHandler)
    except PermissionError:
        print(f"[WARN] Khong du quyen mo Port {port} tren he thong.")
        fallback_port = 8080
        print(f"[WARN] Chuyen sang chay tren Port thay the: {fallback_port}")
        port = fallback_port
        server = ThreadingHTTPServer((args.host, port), ESP32HttpHandler)
    except OSError as e:
        print(f"[WARN] Port {port} dang bi chiem: {e}")
        fallback_port = 8080
        print(f"[WARN] Chuyen sang chay tren Port thay the: {fallback_port}")
        port = fallback_port
        server = ThreadingHTTPServer((args.host, port), ESP32HttpHandler)

    print_banner(args.host, port)

    # Chạy vòng lặp nền cập nhật cảm biến & Firebase
    bg_thread = threading.Thread(target=background_loop, daemon=True)
    bg_thread.start()

    # Chạy HTTP Server trong luồng riêng
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()

    # Chạy CLI tương tác trên luồng chính
    if not args.no_cli:
        cli_loop()
    else:
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
