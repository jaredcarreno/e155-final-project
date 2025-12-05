// STM32L432KC_ADC.h
// Header for ADC functions
// Emma Angel
// eangel@hmc.edu
// 12/5/2025

#ifndef STM32L4_ADC_H
#define STM32L4_ADC_H

#include <stdint.h>
#include <stm32l432xx.h>

///////////////////////////////////////////////////////////////////////////////
// Function prototypes
///////////////////////////////////////////////////////////////////////////////

/** -------------------------------------------------------------------------

* @brief  Initializes ADC1 for continuous sampling on channel 5 using DMA.
*
* The ADC is configured for:
* * 12-bit resolution
* * Continuous conversion mode
* * Right-aligned data
* * Channel 5 (PC0) sampling at 12.5 ADC cycles
* * DMA circular mode enabled
*
*/
void ADCInit();

/** -------------------------------------------------------------------------

* @brief  Enables ADC1 after it has been initialized.
*
* Clears the ADRDY flag and sets the ADEN bit in ADC1->CR.
* This function is  used when the ADC has already been configured
* (e.g., via ADC_Init) and then to turn it on again to restart
* conversions.
* ---
*/
void ADCEnable();

#endif