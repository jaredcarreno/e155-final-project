#define STM32L452xx 1
#include "stm32l4xx.h"
#include "main.h"

volatile float v_lvl[2];
volatile uint16_t adc_val[2];
volatile uint8_t adc_buffer[1024]; // needs to be unint8 so that its 8 bit samples

// processed buffers 
uint8_t proc_buf_A[512];
uint8_t proc_buf_B[512];

volatile uint8_t dma_flag = 0;  
// 1 = half full, 2 = full
// ADDING BUTTON
#define BUTTON_PIN  PA5   // for now


void ADC_Init(void);
void ADC_enable (void);
void DMA_Init (void);
void DMA_Config(void);
void process_block(volatile uint8_t *data, uint32_t size);
// void DMA_Config (volatile uint32_t srcAdd, volatile uint32_t destAdd, volatile uint16_t size);

static inline void copy_u16(uint8_t *dst, uint16_t *src, uint32_t count);


int main(void)
{
    SystemInit();
    // ADDING BUTTON
    gpioEnable(GPIO_PORT_A);
    pinMode(BUTTON_PIN, GPIO_INPUT);

    initTIM(TIM15);

    DMA_Init();
    DMA_Config();
    ADC_Init();
    initSPI(2, 0, 0); // setting baud rate to 2 for now

    while (1)
    {
    if (!digitalRead(BUTTON_PIN))
    {
      // ----- STOP SEQUENCE -----

      // 1. Stop ADC
      ADC1->CR |= ADC_CR_ADSTP;
      while (ADC1->CR & ADC_CR_ADSTP);

      // 2. Disable DMA
      DMA1_Channel1->CCR &= ~DMA_CCR_EN;

      // 3. Clear DMA flags
      DMA1->IFCR = DMA_IFCR_CHTIF1 | DMA_IFCR_CTCIF1;
      continue;
      }
    else
    {
      // ----- START SEQUENCE -----

      // If ADC isn't running, restart it properly
      if (!(ADC1->CR & ADC_CR_ADSTART))
      {
          // Reset DMA length
          DMA1_Channel1->CNDTR = 1024;

          // Re-enable DMA channel
          DMA1_Channel1->CCR |= DMA_CCR_EN;

          // Start ADC conversions
          ADC1->CR |= ADC_CR_ADSTART;
          }
    }


    if (dma_flag == 1)
    {
        dma_flag = 0;
        copy_u16(proc_buf_A, (uint16_t*)&adc_buffer[0], 512);
        printf("DMA buff halfway\n");
    }
    else if (dma_flag == 2)
    {
        dma_flag = 0;
        copy_u16(proc_buf_B, (uint16_t*)&adc_buffer[512], 512);
        printf("DMA buff full\n");
    }
  }

    //while (1)
    //{
    //      //    // Just convert the first two DMA samples 
    //      // v_lvl[0] = (3.3 * adc_buffer[0]) / 4095.0f;
    //      // v_lvl[1] = (3.3 * adc_buffer[1]) / 4095.0f;
    //      // printf("ADC Values: %u, %u\n", adc_buffer[0], adc_buffer[1]);
    //      // printf("Voltage Levels: %.3f V, %.3f V\n", v_lvl[0], v_lvl[1]);
    //    if (dma_flag == 1)
    //    {
    //        dma_flag = 0;

    //        // DMA finished samples 0–511
    //        copy_u16(proc_buf_A, (uint16_t*)&adc_buffer[0], 512);
    //        printf("DMA buff halfway");

    //        // process_block(proc_buf_A, 512);
    //    }
    //    else if (dma_flag == 2){
    //        dma_flag = 0;

    //        // DMA finished samples 512–1023
    //        printf("DMA buff full");
    //        copy_u16(proc_buf_B, (uint16_t*)&adc_buffer[512], 512);

    //        // process_block(proc_buf_B, 512);
    //    }
}

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

    /* --- 11. Start conversions --- */
    // ADDING BUTTON - wait until button to start ADC
    // ADC1->CR |= (1<<2);                // ADSTART
}


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

void ADC_enable (void)
{ // same
  ADC1->ISR |= (1<<0);
  ADC1->CR  |= (1<<0);
  // delay_millis(TIM2, 10);
}


void DMA1_Channel1_IRQHandler(void)
{
    // Half buffer complete
    if (DMA1->ISR & DMA_ISR_HTIF1)
    {
        DMA1->IFCR = DMA_IFCR_CHTIF1;
        process_block(adc_buffer, 512);
        dma_flag = 1;

    }

    // Full buffer complete
    if (DMA1->ISR & DMA_ISR_TCIF1)
    {
        DMA1->IFCR = DMA_IFCR_CTCIF1;
        process_block(&adc_buffer[512], 512);
        dma_flag = 2;

    }
}


static inline void copy_u16(uint8_t *dst, uint16_t *src, uint32_t count)
{
    for (uint32_t i = 0; i < count; i++) {
        dst[i] = src[i];
    }
}

// new process block for the spi 
void process_block(volatile uint8_t *data, uint32_t size)
{
    for (uint32_t i = 0; i < size; i++)
    {
        spiSendReceive(data[i]);   // send each ADC byte over SPI
        printf("SPI sending data: %u\n", data[i]);
    }
}