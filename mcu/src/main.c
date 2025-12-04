// tim2_interrupt_test.c
// Example: Timer 2 interrupt at 16 kHz
// Matches style of the EXTI example you provided

#include <stdio.h>
#include "main.h"

volatile uint32_t tim2_count = 0;

void initTIM2_16kHz(void);

int main(void)
{
    configureFlash();
    configureClock();
    gpioEnable(GPIO_PORT_A);
    gpioEnable(GPIO_PORT_B);
    gpioEnable(GPIO_PORT_C);

    // =============================
    // Enable TIM2 clock (APB1)
    // =============================
    RCC->APB1ENR1 |= RCC_APB1ENR1_TIM2EN;

    // Initialize TIM2 for 16 kHz interrupt
    initTIM2_16kHz();

    // =============================
    // Enable interrupts globally
    // =============================
    __enable_irq();

    printf("===== Timer2 16 kHz Interrupt Test =====\n");

    // Main loop does nothing
    while(1)
    {
        delay_millis(TIM15, 1000);
        printf("Main alive... tim2_count = %lu\n", tim2_count);
    }
}


// ============================================================
// Configure TIM2 to generate update event at 16 kHz
// ============================================================
void initTIM2_16kHz(void)
{
    // TIM2 runs from APB1 = 80 MHz system clock
    // PSC = 4 → timer clock becomes 80MHz / 5 = 16 MHz
    // ARR = 999 → interrupt rate = 16 MHz / 1000 = 16 kHz

    TIM2->PSC = 4;        // divide by (PSC+1)=5
    TIM2->ARR = 999;      // auto-reload
    TIM2->CNT = 0;        // reset counter

    // Enable update interrupt
    TIM2->DIER |= TIM_DIER_UIE;

    // ===============================
    // Enable TIM2 IRQ in NVIC
    // (matches EXACT structure of EXTI example)
    // ===============================
    NVIC->ISER[0] |= (1 << TIM2_IRQn);

    // Start timer
    TIM2->CR1 |= TIM_CR1_CEN;
}


// ============================================================
// TIMER 2 INTERRUPT HANDLER (fires at 16 kHz)
// ============================================================
void TIM2_IRQHandler(void)
{
    // Check update interrupt flag
    if (TIM2->SR & TIM_SR_UIF)
    {
        TIM2->SR &= ~TIM_SR_UIF;  // clear flag

        tim2_count++;

        // PRINT (beware: UART extremely slow)
        printf("TIM2 ISR fired! count=%lu\n", tim2_count);
    }
}
