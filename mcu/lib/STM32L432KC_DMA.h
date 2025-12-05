// STM32L432KC_DMA.h
// Header for DMA functions
// Emma Angel
// eangel@hmc.edu
// 12/5/2025

#ifndef STM32L4_DMA_H
#define STM32L4_DMA_H

#include <stdint.h>
#include <stm32l432xx.h>

/** -------------------------------------------------------------------------

* @brief  Initializes DMA1 Channel 1 for ADC data transfers.
*
* This function enables the DMA1 clock and configures Channel 1 to receive
* ADC conversion data in circular mode. The DMA is set up for:
* * Peripheral-to-memory transfers
* * Circular buffering
* * 8-bit memory and peripheral data size
* * Memory address increment
* * Half-transfer and full-transfer interrupts
*
* The DMA channel remains disabled at the end of this function so that
* DMA_Config() can safely set buffer addresses and transfer size before
* enabling it.
*
* The corresponding interrupt (DMA1_Channel1_IRQn) is enabled in the NVIC.
* ---

*/
void DMA_Init(void)
{
...
}

/** -------------------------------------------------------------------------

* @brief  Configures the DMA transfer parameters for ADC sampling.
*
* This function sets the DMA1 Channel 1 transfer length (CNDTR), assigns the
* ADC data register as the peripheral source, and points the memory address
* to the user-provided ADC buffer.
*
* After the buffer, peripheral address, and transfer size are configured,
* the DMA channel is enabled, allowing ADC conversions to automatically
* populate the memory buffer via DMA.
* ---

*/
void DMA_Config(void)
{
...
}
