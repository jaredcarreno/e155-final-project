// DS1722.c
// Emma Angel
// eangel@hmc.edu
// 12/1
// Defines the functions for the DAC60501 to configure chip and send voltages

#include "STM32L432KC_SPI.h"
#include "STM32L432KC_GPIO.h"
#include "STM32L432KC_TIM.h"
#include "STM32L432KC_DAC60501.h"
#include "stdio.h"


// function defintions

// clock in on the falling edge
// clock idle high
// CS active low
// Clock up to 50MHz in SPI mode
// internal 2.5V reference
// Asynchronous mode: DAC_SYNC_EN = 0 (default) DAC updates immediately 
// REF_PWDWN - turn off internal reference address 3h
// series resistor greater than 1kohm whne using external voltage reference 
// use a minimum 150-nF capacitor between the reference output and AGND
// SOFT_RESET - for software reset 
// input shift register is 24 bits
// void configureDAC(){
//    // configure SPI
//    initSPI(5, 1, 0); // br = 1 (fclk/2), CPOL = 1 (idle high), CPHA = 0 (clocked on falling edge)
//    // manually set chip select high 
//    digitalWrite(SPI_CS, 1);
//    // set buffer and gain
//    // spiWrite24(GAIN, REF_DIV_BUFF_GAIN); // should set a gain of 2
//}

void configureDAC()
{
    // Configure SPI mode 2 (CPOL=1, CPHA=0)
    initSPI(7, 0, 1);
    // initTIM(TIM15);

    // Chip select high
    digitalWrite(SPI_CS, 1);

    // settle 
    delay_millis(TIM15, 1000);

    //// Reset DAC
    spiWrite24(TRIGGER, SOFT_RESET);

    // settle 
    delay_millis(TIM15, 1000);

    // SYNC MODE DAC_SYNC_EN
    spiWrite24(SYNC, DAC_SYNC_EN);

    //// CONFIG REG
    spiWrite24(CONFIG, REF_PWDWN); // make sure internal reference on and DAC not in power down mode

    //// GAIN REG 
    spiWrite24(GAIN, REF_DIV_BUFF_GAIN); // set the ref div to 1 and the gain to 2
}


void setDAC(float voltage)
{
    const float VREF = 2.5f;   // VREFIO (internal)
    const float DIV  = 1.0f;   // REF-DIV bit (1 => not divided). Use 2.0f if REF-DIV=1 divides by 2.
    const float BUFFGAIN = 2.0f;   // BUFF-GAIN = 1 => gain = 2 (per your setting)

    // Compute DAC code using denominator (2^N - 1)
    float code_f = (voltage * (float)4095) / ((VREF / DIV) * BUFFGAIN);

    // Clamp and round
    if (code_f < 0.0f) code_f = 0.0f;
    if (code_f > (float)4095) code_f = (float)4095;
    uint16_t dacCode = (uint16_t)(code_f + 0.5f); // round to nearest
    printf("DAC code = %u (0x%03X)\n", dacCode, dacCode);


    // Left-align 12-bit code into 16-bit data field: DATA[15:0] = DATA[11:0] << 4
    uint16_t dataField = (uint16_t)(dacCode << 4);

    // Send to DAC (24-bit frame: addr, MSB, LSB)
    spiWrite24(DAC_REG, dataField);
}
