// STM32L432KC_DMA.c
// Source for DMA functions
// Emma Angel
// eangel@hmc.edu
// 12/5/2025

#include "STM32L432KC_RCC.h"
#include "STM32L432KC_GPIO.h"


void DMA_Init(void)
{
    RCC->AHB1ENR |= (1 << 0); // enable DMA1

    DMA1_Channel1->CCR &= ~(1 << 0); // disable channel

    // Direction = Peripheral-to-Memory (0)
    DMA1_Channel1->CCR &= ~(1 << 4);

    DMA1_Channel1->CCR |=  (1 << 5);  // circular mode
    DMA1_Channel1->CCR |=  (1 << 7);  // memory increment

    // PSIZE = 16-bit, MSIZE = 16-bit THIS NEEDS TO BE 8 bt

    DMA1_Channel1->CCR &= ~((1 << 8) | (1 << 10)); // setting this to 8 bit size 
    // DMA1_Channel1->CCR |=  ((0 << 8) | (0 << 10));

    // Adding interrupt configuration
    DMA1_Channel1->CCR |= (1 << 1);  // TCIE (full transfer)
    DMA1_Channel1->CCR |= (1 << 2);  // HTIE (half transfer)

    NVIC_EnableIRQ(DMA1_Channel1_IRQn);
}

void DMA_Config(void)
{
    DMA1_Channel1->CCR &= ~(1 << 0); // disable DMA

    DMA1_Channel1->CNDTR = 1024; // size of transfer 
    DMA1_Channel1->CPAR  = (uint32_t)&ADC1->DR; // address of peripheral
    DMA1_Channel1->CMAR  = (uint32_t)adc_buffer; // address of memory buffer

    DMA1_Channel1->CCR |= (1 << 0); // enable channel
}