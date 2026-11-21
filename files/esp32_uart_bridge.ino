// Puente USB (COM) <-> UART para ESP32-S3 N16R8
// Pantalla TX -> GPIO18 (RX del ESP)
// ESP GPIO17 (TX) -> RX de la pantalla (con 1k en serie)
// GND del ESP -> GND de la pantalla
//
// SOLO USB SERIE (COM). El modo WiFi/Telnet se conserva como referencia, pero
// no funciono: Tera Term conectaba por WiFi, no mostraba los comandos
// escritos y la consola no respondia de forma fiable. Usar siempre el COM.
//
// IMPORTANTE: sustituir los valores de WiFi SOLO si se quiere experimentar.
// No son las credenciales reales y no son necesarias para el volcado.

#include <WiFi.h>

// --- CONFIGURACION WIFI (NO USAR; solo referencia) ---
const char* ssid     = "TU_WIFI_SSID";
const char* password = "TU_WIFI_PASSWORD";
const uint16_t PUERTO_TCP = 23;

WiFiServer server(PUERTO_TCP);
WiFiClient client;

#define PIN_RX   18
#define PIN_TX   17
#define PIN_BOOT 0

const unsigned long BAUDS[] = {115200, 921600, 1500000, 57600, 230400, 9600};
const int N_BAUDS = sizeof(BAUDS) / sizeof(BAUDS[0]);
int idx = 0;                      // 115200 por defecto
uint8_t buf[512];
bool autoStopUboot = true;        // se apaga al recibir cualquier tecla desde el PC

void abrirUart() {
  Serial1.end();
  Serial1.setRxBufferSize(16384);
  Serial1.begin(BAUDS[idx], SERIAL_8N1, PIN_RX, PIN_TX);
}

void logDual(const char* msg) {
  Serial.print(msg);
  if (client && client.connected()) client.print(msg);
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_BOOT, INPUT_PULLUP);
  abrirUart();

  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);
  unsigned long inicio = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - inicio < 15000) delay(250);
  if (WiFi.status() == WL_CONNECTED) {
    server.begin();
    server.setNoDelay(true);
  }
}

void loop() {
  static bool conectadoUSB = false;
  if (Serial && !conectadoUSB) {
    conectadoUSB = true;
    delay(200);
    Serial.printf("\r\n[UART a %lu baudios - AutoStop U-Boot ACTIVO]\r\n", BAUDS[idx]);
    if (WiFi.status() == WL_CONNECTED)
      Serial.printf("[WiFi LISTO -> %s:%d] (NO USAR: solo COM)\r\n",
                    WiFi.localIP().toString().c_str(), PUERTO_TCP);
    else
      Serial.println("[WiFi ERROR -> no se pudo conectar; usar COM]");
  }
  if (!Serial) conectadoUSB = false;

  if (server.hasClient()) {
    if (!client || !client.connected()) {
      if (client) client.stop();
      client = server.available();
      client.setNoDelay(true);
      client.printf("\r\n[Conectado por WiFi | UART a %lu baudios | AutoStop: %s]\r\n",
                    BAUDS[idx], autoStopUboot ? "ACTIVO" : "DETENIDO");
    } else {
      WiFiClient rechazo = server.available();
      rechazo.println("\r\n[Ocupado: ya hay otra sesion conectada]");
      rechazo.stop();
    }
  }

  // Ráfaga cada 10 ms para atrapar U-Boot antes de "Starting kernel"
  static unsigned long tBurst = 0;
  if (autoStopUboot && (millis() - tBurst >= 10)) {
    Serial1.write(' ');
    tBurst = millis();
  }

  // UART -> PC (USB y WiFi)
  int n = Serial1.available();
  if (n > 0) {
    n = Serial1.readBytes(buf, min(n, (int)sizeof(buf)));
    Serial.write(buf, n);
    if (client && client.connected()) client.write(buf, n);
  }

  // PC (USB) -> UART
  n = Serial.available();
  if (n > 0) {
    if (autoStopUboot) {
      autoStopUboot = false;
      logDual("\r\n[AutoStop detenido - Consola libre]\r\n");
    }
    n = Serial.readBytes(buf, min(n, (int)sizeof(buf)));
    Serial1.write(buf, n);
  }

  // PC (WiFi) -> UART (solo referencia)
  if (client && client.connected()) {
    n = client.available();
    if (n > 0) {
      if (autoStopUboot) {
        autoStopUboot = false;
        logDual("\r\n[AutoStop detenido - Consola libre]\r\n");
      }
      n = client.read(buf, min(n, (int)sizeof(buf)));
      Serial1.write(buf, n);
    }
  }

  // BOOT: cambiar velocidad con pulsación larga (1,5 s)
  static unsigned long tPress = 0;
  static bool cambiado = false;
  if (digitalRead(PIN_BOOT) == LOW) {
    if (tPress == 0) tPress = millis();
    if (!cambiado && millis() - tPress >= 1500) {
      cambiado = true;
      idx = (idx + 1) % N_BAUDS;
      abrirUart();
      char msg[64];
      snprintf(msg, sizeof(msg), "\r\n[UART a %lu baudios]\r\n", BAUDS[idx]);
      logDual(msg);
    }
  } else {
    tPress = 0;
    cambiado = false;
  }
}
