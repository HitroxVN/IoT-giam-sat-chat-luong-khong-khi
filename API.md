# API — Hệ thống giám sát chất lượng không khí (ESP32)

REST API chạy trực tiếp trên **ESP32**, cổng **80**. Cùng một bộ JSON được
dùng cho cả HTTP lẫn Firebase, nên dữ liệu hai nguồn luôn khớp nhau.

## Địa chỉ

```
http://<IP-CỦA-ESP>/api/...
```

IP in ra Serial Monitor khi WiFi kết nối:

```
[WiFi] OK - IP: 192.168.1.100
[HTTP] Server: http://192.168.1.100:80
```

Không có mDNS, không có tên miền — phải dùng IP. IP do router cấp động nên
có thể đổi sau mỗi lần khởi động lại. Muốn cố định thì đặt static IP trong
router theo MAC của ESP.

ESP **không phục vụ trang web** — mọi path trả JSON, kể cả `/`. Giao diện
chạy trên máy người dùng, không nằm trên firmware.

---

## Quy ước chung

### Quy tắc về HTTP method

| Method | Dùng cho |
|---|---|
| `GET` | Chỉ đọc. Thay đổi trạng thái phần cứng **không** dùng `GET`. |
| `POST` | Mọi lệnh điều khiển: LED, còi, Firebase, ngưỡng. |

Lý do: `GET` có thể bị kích hoạt nhầm bởi crawler, prefetch của trình duyệt
hay người gõ nhầm URL. Bật còi hay tắt Firebase là việc thay đổi trạng thái
thật nên phải là `POST`.

### Tham số truyền vào

Mọi tham số nhận được **cả hai cách** — query string hoặc form body:

```
POST /api/led?state=on      ← query string
POST /api/led               ← form body
     state=on
```

### CORS

Mọi response đều kèm `Access-Control-Allow-Origin: *` — cần thiết khi gọi
API từ một trang web mở bằng `file://` hoặc từ domain khác.

### Mã lỗi

| Mã | Khi nào |
|---|---|
| `200` | Thành công |
| `400` | Thiếu tham số, hoặc giá trị không hợp lệ |
| `404` | Path không khớp route nào, hoặc `key` không tồn tại |

Body lỗi có dạng `{"error":"..."}` — **không** có trường `ok`.

### Trạng thái số đo

| Trường | Kiểu | Ý nghĩa |
|---|---|---|
| `valid` | boolean | `false` nghĩa là cảm biến đọc lỗi lần này. Các giá trị đo khi đó **không đáng tin**, không phải số 0 thật. |

---

## Endpoint

| Method | Path | Việc |
|---|---|---|
| `GET` | `/api/data` | Toàn bộ trạng thái hiện tại |
| `GET` | `/api/mq` | Cả 3 cảm biến MQ |
| `GET` | `/api/mq/{key}` | Một cảm biến MQ |
| `POST` | `/api/led` | Điều khiển đèn |
| `POST` | `/api/buzzer` | Điều khiển còi |
| `POST` | `/api/fan` | Điều khiển quạt (chân D18) |
| `GET` \| `POST` | `/api/firebase` | Trạng thái / bật-tắt đồng bộ |
| `POST` | `/api/threshold` | Sửa ngưỡng cảnh báo |
| `GET` \| `POST` | `/api/calibrate` | Hiển thị / Hiệu chuẩn lại R0 trong không khí sạch |

---

## `GET /api/data`

Trả toàn bộ trạng thái. Đây cũng chính là nội dung gửi lên Firebase.

**Response `200`**

```json
{
  "device": "esp32-air-quality",
  "uptime_ms": 128400,
  "wifi": {
    "connected": true,
    "ssid": "HUNRE NOI BO 3",
    "rssi": -58
  },
  "env":   { "valid": true, "temp_c": 29.40, "humidity": 68.20 },
  "dust":  { "valid": true, "pm2_5": 78.3, "pm10": 121.7 },
  "gas":   { "co2_ppm": 1180.5, "lpg_ppm": 355.2, "co_ppm": 44.8 },
  "aqi":   { "value": 148, "category": "Kém" },
  "alert": { "level": "danger", "danger": true, "led": 1, "buzzer": 1, "fan": 1 },
  "firebase": { "enabled": true, "last_code": 200, "interval_ms": 30000 },
  "thresholds": { "co2": 1500, "lpg": 400, "co": 50, "pm2_5": 50, "pm10": 100 }
}
```

| Trường | Kiểu | Ý nghĩa |
|---|---|---|
| `uptime_ms` | number | Thời gian chạy, mili giây |
| `wifi.rssi` | number | Cường độ tín hiệu dBm. `0` khi mất kết nối |
| `env.temp_c` | number | Nhiệt độ °C. Kiểm tra `env.valid` trước khi dùng |
| `dust.pm2_5`, `dust.pm10` | number | µg/m³. Kiểm tra `dust.valid` trước khi dùng |
| `aqi.value`, `aqi.category` | number, string | Chỉ số và phân loại **VN_AQI** theo Quyết định 1459/QĐ-TCMT (Bộ TN&MT) |
| `alert.level` | string | Mức cảnh báo Backend: `"safe"` (<80%), `"warning"` (≥80%), `"danger"` (≥100%) |
| `alert.danger` | boolean | `true` khi ở mức nguy hiểm (`alert.level == "danger"`) |
| `alert.led`, `alert.buzzer`, `alert.fan` | `0` \| `1` | Trạng thái chân **thực tế** lúc này (LED sáng khi warning/danger; Buzzer & Quạt chỉ bật khi danger) |
| `firebase.last_code` | number | Mã HTTP của lần gửi Firebase gần nhất. `0` = chưa gửi lần nào |
| `thresholds.pm10` | number | Ngưỡng tham chiếu — **không** kích hoạt cảnh báo (xem phần Ngưỡng) |

---

## `GET /api/mq`

Trả cả 3 cảm biến khí.

**Response `200`**

```json
{
  "sensors": [
    { "key": "mq135", "gas": "CO2", "ppm": 701.2, "adc": 2130,
      "r0": 181.41, "a": 110.470, "b": -2.862, "valid": true },
    { "key": "mq2",   "gas": "LPG", "ppm": 7.0,   "adc": 2380,
      "r0": 14.45,  "a": 574.250, "b": -2.222, "valid": true },
    { "key": "mq7",   "gas": "CO",  "ppm": 4.0,   "adc": 3150,
      "r0": 3.32,   "a": 99.040,  "b": -1.518, "valid": true }
  ]
}
```

| Trường | Kiểu | Ý nghĩa |
|---|---|---|
| `key` | string | Định danh dùng cho URL và cho `POST /api/threshold` |
| `gas` | string | Khí đang đo |
| `ppm` | number | Nồng độ quy đổi. **Âm** nghĩa là lần đọc lỗi |
| `adc` | number | Giá trị ADC thô **0–4095** (12 bit), không phải ppm |
| `r0` | number | Điện trở cảm biến trong không khí sạch, đã hiệu chuẩn |
| `a`, `b` | number | Hệ số đường đặc tuyến `ppm = a · (Rs/R0)^b` |

## `GET /api/mq/{key}`

Cùng cấu trúc nhưng trả về **một đối tượng**, không có mảng bọc ngoài.

```
GET /api/mq/mq135
GET /api/mq/mq2
GET /api/mq/mq7
```

`key` không hợp lệ → `404`.

> `r0`, `a`, `b` là hằng số compile-time, lấy từ khai báo trong `main.ino`.
> Sửa chúng phải nạp lại firmware — API không thay đổi được.

---

## `POST /api/led` · `POST /api/buzzer` · `POST /api/fan`

Tham số `state`, nhận `on`/`off`/`auto` (hoặc `1`/`0`/`true`/`false`).

```
POST /api/led?state=on
POST /api/buzzer?state=off
POST /api/fan?state=auto
```

| `state` | Ý nghĩa |
|---|---|
| `on` | Ghim chân ở mức cao |
| `off` | Ghim chân ở mức thấp |
| `auto` | Chạy theo cờ `alert.danger` |

**Về chế độ `auto`:** khi đang ở `on` hoặc `off`, cảnh báo ngưỡng **vẫn được
tính và vẫn xuất hiện trong `alert.danger`**, nhưng không ghi đè lên chân — đó
lý do có cờ `auto` để trả lại quyền điều khiển cho ngưỡng.

Giá trị sai → `400`.

---

## `GET|POST /api/firebase`

`GET` trả về trạng thái. `POST` bật/tắt đồng bộ.

```
POST /api/firebase?state=off    # tắt
POST /api/firebase?state=on     # bật — gửi ngay một mẫu, không chờ hết chu kỳ
```

`auto` **không áp dụng** ở đây → `400`. Firebase không có chế độ để cảm biến
tự quyết.

esp32/
├── latest/     ← ghi đè mỗi lần, luôn là mẫu mới nhất
├── history/    ← push, mỗi lần thêm một node mới
└── thresholds/ ← lưu trữ các ngưỡng cài đặt, đồng bộ 2 chiều với ESP32
```

Nội dung của `latest` và `history` giống hệt body của `GET /api/data`. Node `thresholds` có dạng:
```json
{"co2": 1500, "lpg": 400, "co": 50, "pm2_5": 50, "pm10": 100}
```

| Mã trả về | Nghĩa |
|---|---|
| `200` | Thành công |
| `401` | Token sai hoặc hết hạn |
| `403` | Database rules chặn ghi |
| `404` | Sai URL hoặc sai path |

> `history` **không tự dọn dẹp** — mỗi lần gửi thêm một node. Ở chu kỳ 30
> giây là khoảng 2.880 node mỗi ngày. Nếu chỉ cần vài giờ gần nhất thì phải
> thêm logic xoá.

---

## `POST /api/threshold`

Sửa ngưỡng cảnh báo. Sửa xong ESP dùng ngay, **không cần nạp lại firmware**.

```
POST /api/threshold?key=co2&value=1200
```

| Tham số | Bắt buộc | Ý nghĩa |
|---|---|---|
| `key` | có | Chỉ số cần sửa (xem bảng dưới) |
| `value` | có | Giá trị mới, số **> 0** |

| `key` | Chỉ số | Đơn vị | Mặc định |
|---|---|---|---|
| `mq135` | CO₂ | ppm | 1500 |
| `mq2` | LPG | ppm | 400 |
| `mq7` | CO | ppm | 50 |
| `pm2_5` | PM2.5 | µg/m³ | 50 |
| `pm10` | PM10 | µg/m³ | 100 |

Lỗi trả `400` (`value` rỗng, không phải số, có ký tự thừa, hoặc ≤ 0) hoặc
`404` (`key` không tồn tại).

### Điều gì **không** kích hoạt cảnh báo

`alert.danger` chỉ được đặt khi một trong bốn chỉ số vượt ngưỡng:

```
CO2 ≥ thresholds.co2
LPG ≥ thresholds.lpg
CO  ≥ thresholds.co
PM2.5 ≥ thresholds.pm2_5   (và dust.valid = true)
```

**`thresholds.pm10` không kích hoạt cảnh báo.** PM10 luôn ≥ PM2.5, nên nếu
kêu theo cả hai thì PM2.5 vượt sẽ kêu hai lần, còn PM10 vượt mà PM2.5 chưa
vượt thì không có ý nghĩa an toàn. `pm10` chỉ để tham chiếu hiển thị.

### Đồng bộ và lưu trữ lâu dài qua Firebase (`esp32/thresholds`)

Mỗi khi thay đổi ngưỡng qua `POST /api/threshold`, thiết bị sẽ **tự động đẩy ngay các ngưỡng mới lên Firebase Realtime Database** tại path `esp32/thresholds`.

Khi ESP32 khởi động lại (`setup()`), hệ thống sẽ **tự động tải lại các ngưỡng đã cấu hình từ Firebase về áp dụng**, giúp cài đặt được duy trì liên tục qua các lần mất điện hay khởi động lại. Nếu trên Firebase chưa có dữ liệu, ESP32 sẽ khởi tạo bằng các giá trị mặc định.

---

## `GET|POST /api/calibrate`

Hiệu chuẩn lại điện trở R0 đồng thời cho cả 3 cảm biến MQ trong không khí sạch mà **không cần nạp lại firmware**.

```bash
# Xem thông số R0 và CleanAirRatio hiện tại của cả 3 cảm biến
GET /api/calibrate

# Hiệu chuẩn đồng thời cả 3 cảm biến (lấy 10 mẫu trong không khí sạch)
POST /api/calibrate

# Tùy chọn số lượng mẫu (ví dụ 15 mẫu)
POST /api/calibrate?samples=15
```

> **Cách hiệu chuẩn vật lý**:
> Đặt thiết bị trong môi trường không khí sạch thoáng đãng (hoặc ngoài trời trong lành) trong 10-20 giây, sau đó gửi lệnh `POST /api/calibrate` hoặc gõ `calib` trên Serial Monitor.

---

## Cảnh báo về độ chính xác

Các giá trị `ppm` **không phải ppm thật**. Đường cong
`ppm = a · (Rs/R0)^b` lấy từ datasheet, còn `r0` đo thủ công trong không khí
sạch. Sai số có thể gấp đôi hoặc hơn, và mỗi sensor MQ cho kết quả khác nhau.

Nếu cần ngưỡng đáng tin, hãy đối chiếu với một mẫu biết trước — đốt LPG cụ
thể rồi đọc lại qua `/api/mq`, hoặc dùng ppm meter.

---

## Ví dụ

```bash
IP=http://192.168.1.100

curl $IP/api/data
curl $IP/api/mq
curl $IP/api/mq/mq135

curl -X POST "$IP/api/buzzer?state=off"
curl -X POST "$IP/api/led?state=auto"
curl -X POST "$IP/api/firebase?state=off"
curl -X POST "$IP/api/threshold?key=co2&value=1200"
```

Từ trình duyệt:

```javascript
const base = 'http://192.168.1.100';

await fetch(base + '/api/data').then(r => r.json());

await fetch(base + '/api/threshold?key=pm2_5&value=35', { method: 'POST' });

await fetch(base + '/api/led?state=on', { method: 'POST' });
```