// STM32L432KC_ADC.c
// Source for ADC functions
// Emma Angel
// eangel@hmc.edu
// 12/5/2025

#include "STM32L432KC_RCC.h"
#include "STM32L432KC_GPIO.h"



void ADC_Init(void)
{
    /* --- 1. Enable clocks --- */
    RCC->AHB2ENR |= (1<<0) | (1<<2) | (1<<13);  
    // GPIOA | GPIOC | ADC enable

    /* --- 2. Set ADC clock source (System Clock = 80 MHz) --- */
    RCC->CCIPR &= ~(3 << 28);
    RCC->CCIPR |=  (3 << 28);     // ADC clock = SYSCLK
    //  ADC1_COMMON->CCR |= (10<<18); // Set ADC Prescaler to 128, 80Mhz/128 = 625kHz
    // Need to disable ADC first maybe?


    /* --- 3. Configure ADC prescaler (safe: /4) --- */ // FIX THE PRESCALER
    ADC1_COMMON->CCR &= ~(0xF << 18); 
    ADC1_COMMON->CCR |=  (11 << 18);    // changing prescaler to 256

    /* --- 4. ADC power-up sequence --- */
    ADC1->CR &= ~(1<<29);     // disable deep power-down
    ADC1->CR |=  (1<<28);     // enable voltage regulator
    // delay_millis(TIM15, 10);             // regulator stabilization (required)

    /* --- 5. Resolution, alignment, continuous mode --- */
    ADC1->CFGR &= ~(2 << 3);  // 12-bit, I WANT 8 BIT RES, changing to 2 should be 8-bit res
    ADC1->CFGR |=  (1 << 13); // continuous conversion mode
    ADC1->CFGR &= ~(1 << 5);  // right alignment

    /* --- 6. Sampling time for channel 5 --- */
    ADC1->SMPR1 &= ~(7 << 15);         // clear SMP5
    ADC1->SMPR1 |=  (2 << 15);         // SMP5 = 12.5 cycles (example), I DO WANT 12.5 CYCLES

    /* --- 7. Configure GPIO for analog input (CH5 = PC0) --- */
    GPIOC->MODER &= ~(3 << 0);
    GPIOC->MODER |=  (3 << 0);         // PC0 → analog mode

    /* --- 8. DMA settings (circular mode) --- */

    ADC1->CFGR |=  (1 << 0);           // DMAEN
    ADC1->CFGR |=  (1 << 1);           // DMACFG = circular mode, (same are circular double buffer

    /* --- 9. Configure regular sequence for ONE channel (length = 1) --- */
    ADC1->SQR1 &= ~0xF;                // L = 0 (1 conversion)
    ADC1->SQR1 &= ~(0x1F << 6);        
    ADC1->SQR1 |=  (5 << 6);           // Rank 1 = CH5

    /* --- 10. Enable ADC --- */
    ADC1->ISR |= (1<<0);               // clear ADRDY
    ADC1->CR  |= (1<<0);               // enable ADC

    while (!(ADC1->ISR & (1<<0)));     // wait for ADC ready
}

void ADC_enable (void)
{
  ADC1->ISR |= (1<<0);
  ADC1->CR  |= (1<<0);
}

