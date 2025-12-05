// STM32L432KC_DAC.h
// Header for DAC functions
// Emma Angel
// eangel@hmc.edu
// 12/5/2025

// STM32L432KC.h
// Header for DAC60501

#ifndef STM32L4_DAC60501_H
#define STM32L4_DAC60501_H

#include <stdint.h>
#include <stm32l432xx.h>

// link to datasheet: https://www.ti.com/lit/ds/symlink/dac60501.pdf?HQS=dis-dk-null-digikeymode-dsf-pf-null-wwe&ts=1764587231640&ref_url=https%253A%252F%252Fwww.ti.com%252Fgeneral%252Fdocs%252Fsuppproductinfo.tsp%253FdistId%253D10%2526gotoUrl%253Dhttps%253A%252F%252Fwww.ti.com%252Flit%252Fgpn%252Fdac60501
// Register map Tabl 8-7
#define NOOP    0x00
#define DEVID   0x01
#define SYNC    0x02
#define CONFIG  0x03
#define GAIN    0x04
#define TRIGGER 0x05
#define STATUS  0x07
#define DAC_REG 0x08

// CONFIG REG
#define REF_PWDWN 0x0000// bit 8 when set to 1, this bit disables internal reference
// GAIN REG
#define REF_DIV_BUFF_GAIN 0x0001 // REF-DIV = 0 (refernce voltage unaffected), BUFF-GAIN = 1 (gain of 2)
// TRIGGER REG
#define SOFT_RESET 0x000A
// SYNC REG
#define DAC_SYNC_EN 0x0000

///////////////////////////////////////////////////////////////////////////////
// Function prototypes
///////////////////////////////////////////////////////////////////////////////

/******************************************************

* Function: configureDAC
* ---
* Initializes and configures the DAC60501 device.
*
* * Sets up the SPI peripheral in **Mode 2** (CPOL=1, CPHA=0)
* to match the DAC’s communication requirements.
* * Enables **synchronization mode** so updates occur properly
* with respect to LDAC/SYNC behavior.
* * Configures the **CONFIG register** to enable the internal
* reference and ensure the DAC is not in power-down mode.
* * Configures the **GAIN register** to use:
* ```
   - REF_DIV = 1 (no division of the 2.5 V reference)
  ```
* ```
   - BUFF_GAIN = 2 (output voltage doubled from DAC code)
  ```
*
* This function prepares the DAC to accept code writes.
  ******************************************************/
  void configureDAC();

/********************************************************************

* Function: setDAC
* ---
* Converts a voltage (in volts) into the corresponding 12-bit DAC code
* and transmits it to the DAC60501 over SPI.
* ```
    code = (Vout * 4095) / ( (Vref / DIV) * BUFFGAIN )
  ```
* Input:
* voltage — desired DAC output voltage, in volts.
  ********************************************************************/
  void setDAC(float voltage);


#endif