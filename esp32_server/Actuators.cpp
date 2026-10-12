#include "Actuators.h"
#include "Sensors.h"

Actuator led    = {LED_PIN,    -1, "LED"};
Actuator buzzer = {BUZZER_PIN, -1, "Buzzer"};
Actuator fan    = {FAN_PIN,    -1, "Fan"};

void setupActuators() {
  for (Actuator *a : {&led, &buzzer, &fan}) {
    pinMode(a->pin, OUTPUT);
    digitalWrite(a->pin, LOW);
  }
}

// mode = -1 (auto) hoặc 0/1 (ghi đè tay).
// Ở chế độ auto: LED bật khi warning hoặc danger; Buzzer & Fan chỉ kích hoạt khi danger.
void setActuator(Actuator &a, int mode) {
  a.mode = mode;
  if (mode >= 0) {
    digitalWrite(a.pin, mode ? HIGH : LOW);
  } else {
    if (&a == &led) {
      digitalWrite(a.pin, (r.alertLevel != ALERT_SAFE) ? HIGH : LOW);
    } else {
      digitalWrite(a.pin, (r.alertLevel == ALERT_DANGER) ? HIGH : LOW);
    }
  }
}

void applyAlertToPins() {
  if (led.mode < 0) {
    digitalWrite(led.pin, (r.alertLevel != ALERT_SAFE) ? HIGH : LOW);
  }
  if (buzzer.mode < 0) {
    digitalWrite(buzzer.pin, (r.alertLevel == ALERT_DANGER) ? HIGH : LOW);
  }
  if (fan.mode < 0) {
    digitalWrite(fan.pin, (r.alertLevel == ALERT_DANGER) ? HIGH : LOW);
  }
}
