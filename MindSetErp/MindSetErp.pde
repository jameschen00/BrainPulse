/*
 * MindSetErp.pde
 *
 * Arduino Interface to the Neurosky MindSet EEG headset.
 *
 * Flashes an LED and records event-related potentials from
 * the MindSet. 
 *
 * The "errorRate" measure of signal quality (0 = good)
 * is shown on the built-in LED (LED on means data are good).
 * It also sends selected all the MindSet data measurements 
 * to a host computer via the Teensy USB serial port.
 *
 * 2011.06.23 Bob Dougherty <bobd@stanford.edu> wrote it.
 * 
 */
 
#include <MindSet.h>
#include <SSD1306.h>
#include <Flash.h>

#define VERSION "0.5"

#define DEFAULT_REFRESH_INTERVAL 3

// Sample interval is ~1.95ms (1000/512)
#define FLICKTICS 64
const byte flickPeriod = FLICKTICS;
byte flickCount;
const unsigned long flickDutyMs = 20;
unsigned long flickDutyStartMs;
unsigned long dataReadyMicros;
byte repCount;
long buffer[FLICKTICS];


#if defined(__AVR_AT90USB1286__)
  // Teensy2.0++ has LED on D6
  #define LED_ERR 6
  #define LED_RED 16
  #define LED_GRN 15
  #define LED_BLU 14
  HardwareSerial btSerial = HardwareSerial();
  // Pin definitions for the OLED graphical display
  #define OLED_DC 24
  #define OLED_RESET 25
  #define OLED_SS 20
  #define OLED_CLK 21
  #define OLED_MOSI 22
#elif defined(__AVR_ATmega32U4__)
  // Teensy2.0 has LED on pin 11
  #define LED_ERR 11
  #define LED_RED 9
  #define LED_BLU 4
  #define LED_GRN 5
  HardwareSerial btSerial = HardwareSerial();
  // Pin definitions for the OLED graphical display
  #define OLED_DC 11
  #define OLED_RESET 13
  #define OLED_SS 0
  #define OLED_CLK 1
  #define OLED_MOSI 2
#else
  // Assume Arduino (LED on pin 13)
  #define LED_ERR 13
  #define LED_RED 9
  #define LED_BLU 4
  #define LED_GRN 5
  Serial btSerial = Serial();
  // Pin definitions for the OLED graphical display
  #define OLED_DC 11
  #define OLED_RESET 13
  #define OLED_SS 12
  #define OLED_CLK 10
  #define OLED_MOSI 9
#endif

SSD1306 oled(OLED_MOSI, OLED_CLK, OLED_DC, OLED_RESET, OLED_SS);

#define BAUDRATE 115200


#define SQUARE(a) ((a)*(a))

byte g_displayUpdateInterval;
MindSet g_mindSet;

void setup() {
  // Set up the serial port on the USB interface
  Serial.begin(BAUDRATE);
  Serial << F("*********************************************************\n");
  Serial << F("* MindSet ERP version ") << VERSION << F("\n");
  Serial << F("*********************************************************\n\n");
  Serial << "Starting up...\n";
  btSerial.begin(BAUDRATE);
  
  g_displayUpdateInterval = DEFAULT_REFRESH_INTERVAL;

  // Configure LED pins
  pinMode(LED_RED, OUTPUT);
  pinMode(LED_GRN, OUTPUT);
  pinMode(LED_BLU, OUTPUT);
  pinMode(LED_ERR, OUTPUT);
  
  oled.ssd1306_init(SSD1306_SWITCHCAPVCC);
  oled.display(); // show splashscreen
  
  for(int i=0; i<255; i+=2){
    analogWrite(LED_RED, i);
    analogWrite(LED_GRN, i);
    analogWrite(LED_BLU, i);
    delay(5);
  }
  for(int i=255; i>=0; i-=2){
    analogWrite(LED_RED, i);
    analogWrite(LED_GRN, i);
    analogWrite(LED_BLU, i);
    delay(5);
  }
  
  // Attach the callback function to the MindSet packet processor
  g_mindSet.attach(dataReady);

  Serial << F("MindSet ERP Ready.\n\n");

}

//
// Main program loop. 
//
void loop() {
  // Need a buffer for the line of text that we show.
  static char stringBuffer[SSD1306_LCDLINEWIDTH+1];
  static unsigned long lastDataMicros;
  
  // We just feed bytes to the MindSet object as they come in. It will
  // call our callback whenever a complete data packet has been received and parsed.
  if(btSerial.available()) 
    g_mindSet.process(btSerial.read());
  
  // Turn off the LED if the counter has expired
  if((millis()-flickDutyStartMs)>flickDutyMs){
    analogWrite(LED_RED,0);
    analogWrite(LED_GRN,0);
    analogWrite(LED_BLU,0);
  }
  
  // Raw values from the MindSet are about -2048 to 2047
  if(repCount>=32){
    unsigned long diffMillis = (dataReadyMicros-lastDataMicros)/1000/32;
    Serial << F("\n");
    snprintf(stringBuffer, SSD1306_LCDLINEWIDTH+1, "%02d %02d %02d %04d   ",
              g_mindSet.errorRate()>>2, min(g_mindSet.attention(),99), min(g_mindSet.meditation(),99), diffMillis);
    repCount = 0;
    lastDataMicros = dataReadyMicros;
    //Serial << stringBuffer << F("\n");
    refreshErpDisplay(stringBuffer);
    for(byte i=0; i<flickPeriod; i++){
      // bit-shift division, with rounding:
      Serial << ((buffer[i]+4)>>3) << F(",");
      buffer[i] = 0;
    }

  }
}

// 
// MindSet callback. 
// This function will be called whenever a new data packet is ready.
//
void dataReady() {
  //static char str[64];
  //if(g_mindSet.errorRate()<127 && g_mindSet.attention()>0)
  //  analogWrite(LED_RED, g_mindSet.attention()*2);
  //if(g_mindSet.errorRate()<127 && g_mindSet.meditation()>0)
  //  analogWrite(LED_BLU, g_mindSet.meditation()*2);
     
  if(g_mindSet.errorRate() == 0)
    digitalWrite(LED_ERR, HIGH);
  else
    digitalWrite(LED_ERR, LOW);
  
  buffer[flickCount] += g_mindSet.raw();
  
  dataReadyMicros = micros();
 
  flickCount++;
  if(flickCount>=flickPeriod){
    flickCount = 0;
    repCount++;
  }
  if(flickCount==0){
    analogWrite(LED_RED, 255);
    analogWrite(LED_GRN, 255);
    analogWrite(LED_BLU, 255);
    flickDutyStartMs = millis();
  }
}

void refreshErpDisplay(char *stringBuffer){
  // 0,0 is at the upper left, so we want to flip Y.

  // Clear the graph
  oled.clear();
  
  long bsum=0, bmax=0, bmin=0;
  //for(int i=0; i<flickPeriod; i++){
  //  if(buffer[i]<bmin) bmin = buffer[i];
  //  if(buffer[i]>bmax) bmax = buffer[i];
  //  bsum += buffer[i];
  //}
  //long buffMn = bsum/flickPeriod;
  //long buffScale = (bmax-bmin)/48;
  long buffMn = 0;
  long buffScale = (2048/48);
  //Serial << bsum << F(",") << buffMn << F(",") << buffScale << F("\n");
  for(int i=0; i<flickPeriod; i++){
    // Clip the y-values to the plot area (SSD1306_LCDHEIGHT-1 at the bottom to 16 at the top)
    long curY = SSD1306_LCDHEIGHT - (buffer[i]-buffMn)/buffScale;
    if(curY>SSD1306_LCDHEIGHT-1) curY = SSD1306_LCDHEIGHT-1;
    else if(curY<16) curY = 16;
    // Plot the pixel for the current data point
    oled.setpixel(i, curY, WHITE);
  }
  // Draw the status string at the top:
  oled.drawstring(0, 0, stringBuffer);
  // Finished drawing the the buffer; copy it to the device:
  oled.display();
}


