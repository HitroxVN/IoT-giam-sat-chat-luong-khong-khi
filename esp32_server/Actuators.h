#pragma once

#include "Config.h"
#include "Types.h"

// Các thiết bị ngoại vi điều khiển
extern Actuator led;
extern Actuator buzzer;
extern Actuator fan;

void setupActuators();
void setActuator(Actuator &a, int mode);
void applyAlertToPins();
