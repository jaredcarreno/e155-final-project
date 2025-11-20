#define STM32L452xx 1
#include "stm32l4xx.h"
#include "main.h"

volatile float v_lvl[2];
volatile uint16_t adc_val[2];
volatile uint16_t adc_buffer[512];


void ADC_Init(void);
void ADC_enable (void);
void DMA_Init (void);
void DMA_Config (volatile uint32_t srcAdd, volatile uint32_t destAdd, volatile uint16_t size);

int main (void)
{
    SystemInit();
    initTIM(TIM15);

    DMA_Init();
    DMA_Config((uint32_t)&ADC1->DR, (uint32_t)adc_buffer, 512);

    ADC_Init();   // ADC_Init already does ADSTART

    while (1)
    {
        // Just convert the first two DMA samples 
        v_lvl[0] = (3.3 * adc_buffer[0]) / 4095.0f;
        v_lvl[1] = (3.3 * adc_buffer[1]) / 4095.0f;

        printf("ADC Values: %u, %u\n", adc_buffer[0], adc_buffer[1]);
        printf("Voltage Levels: %.3f V, %.3f V\n", v_lvl[0], v_lvl[1]);
    }
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
    ADC1_COMMON->CCR |=  (9 << 18);    // changing prescaler to 64

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
    ADC1->CFGR |=  (1 << 1);           // DMACFG = circular mode

    /* --- 9. Configure regular sequence for ONE channel (length = 1) --- */
    ADC1->SQR1 &= ~0xF;                // L = 0 (1 conversion)
    ADC1->SQR1 &= ~(0x1F << 6);        
    ADC1->SQR1 |=  (5 << 6);           // Rank 1 = CH5

    /* --- 10. Enable ADC --- */
    ADC1->ISR |= (1<<0);               // clear ADRDY
    ADC1->CR  |= (1<<0);               // enable ADC

    while (!(ADC1->ISR & (1<<0)));     // wait for ADC ready

    /* --- 11. Start conversions --- */
    ADC1->CR |= (1<<2);                // ADSTART
}




void DMA_Init (void)
{
    RCC->AHB1ENR |= (1<<0); // Enable DMA1 clock

    DMA1_Channel1->CCR &= ~(1<<4);      // Data direction: peripheral to memory (P->M)
    DMA1_Channel1->CCR |=  (1<<5);      // Circular mode enable
    DMA1_Channel1->CCR |=  (1<<7);      // Memory increment mode

    // --- Minimal change: Correct P/M size for 16-bit ADC ---
    DMA1_Channel1->CCR &= ~((1<<8) | (1<<10));   // clear PSIZE & MSIZE
    DMA1_Channel1->CCR |=  (1<<8) | (1<<10);     // PSIZE = 16-bit, MSIZE = 16-bit
}

void  DMA_Config (volatile uint32_t srcAdd, volatile uint32_t destAdd, volatile uint16_t size)
{
    DMA1_Channel1->CCR &= ~(1<<0); // disable DMA channel before config (important)

    DMA1_Channel1->CNDTR = size;   // number of transfers (e.g., 512)
    DMA1_Channel1->CPAR  = srcAdd; // address of peripheral (ADC1->DR)
    DMA1_Channel1->CMAR  = destAdd; // address of memory buffer

    DMA1_Channel1->CCR |= (1<<0);  // enable DMA channel
}

void ADC_enable (void)
{ // same
  ADC1->ISR |= (1<<0);
  ADC1->CR  |= (1<<0);
  // delay_millis(TIM2, 10);
}


//int main (void)
//{
//  SystemInit();
//  initTIM(TIM15);
//  ADC_Init();
//  ADC_enable();
//  DMA_Init();

//  while (1)
//  {
//     ADC1->CR |= (1<<2); // start the ADC
//     DMA_Config((uint32_t)&ADC1->DR, (uint32_t)adc_buffer, 512);
//     // DMA_Config(( uint32_t) &ADC1->DR, ( uint32_t) adc_val, 2);

//     // Converting ADC values to V levels.
//     v_lvl[0] = (3.3*adc_buffer[0])/4095;
//     v_lvl[1] = (3.3*adc_buffer[1])/4095;
//     printf("ADC Values: %d, %d\n", adc_buffer[0], adc_buffer[1]);
//     printf("Voltage Levels: %.3f V, %.3f V\n", v_lvl[0], v_lvl[1]);

//  }
//return 0;
//} 

//void ADC_Init (void)
//{
  
//  RCC->AHB2ENR |=  (1<<2) | (1<<0) | (1<<13); // enable GPIOC clock and ADC clock
//  RCC->CCIPR   &= ~(3<<28); // ADC clock source selection ADCSEL
//  RCC->CCIPR   |=  (3<<28); // System clock selected as ADCs clock
//  // Assuming my system clock is the PLL this is a 80MHz
//  ADC1_COMMON->CCR |= (10<<18); // Set ADC Prescaler to 128, 80Mhz/128 = 625kHz


//  ADC1->CR &= ~(1<<29); // disable the deep-power-down by Setting DEEPWD to 0
//  ADC1->CR |=  (1<<0); // disable ADC
//  ADC1->CR |=  (1<<28); // enable the voltage regulator
  
//  ADC1->CFGR  |= (2<<3); // set resolution to 8-bit, RES
//  ADC1->CFGR  |=  (1<<13); // continuous conversion mode, CONT
//  ADC1->CFGR  &= ~(1<<5); // right Alignment, ALIGN
//  // ADC1->SMPR1 &= ~(7<<0) & ~(7<<12); // reset Sampling rate for PC0 & PA0
//  ADC1->SMPR1 &= ~(2<<0); // Set PA0 sampling rate to, set to 12.5 ADC clock cycles, 635kHz/12.5 = 50kHz
//  ADC1->SQR1  &= ~(0xf); // clear register, regular sequence register
//  // ADC1->SQR1  |=  (1<<0); // for 2 channel
//  ADC1->SQR1  |=  (0<<0); // for 1 channel

//  GPIOA->MODER |=  (3<<0); // set analog mode pin PA0
//  GPIOC->MODER &= ~(0xffffffff); // reset the whole register
//  // GPIOC->MODER |=  (3<<0); // set the analog mode pin PC0

//  ADC1->CFGR |=  (1<<1); // Enable DMA circular mode, DMACFG
//  ADC1->CFGR |=  (1<<0); // Enable DMA, DMAEN
//  ADC1->SQR1 &= ~(0x1f<<6) & ~(0xf<<12); // reset the sequence registers
//  ADC1->SQR1 |=  (1<<6) | (5<<12); // set the sequence accordingly to channels
//}
//void DMA_Init (void)
//{
//  RCC->AHB1ENR |= (1<<0); // Enable DMA1 clock

//  DMA1_Channel1->CCR &= ~(1<<4); // Set the data direction (P-M)
//  DMA1_Channel1->CCR |=  (1<<5); // Circullium mode enable
//  DMA1_Channel1->CCR |=  (1<<7); // Enable memory increment Mode
//  DMA1_Channel1->CCR |=  (1<<8) | (1<<10); // peripheral and memory size setting
//}

//void  DMA_Config (volatile uint32_t srcAdd, volatile uint32_t destAdd, volatile uint8_t size)
//{

//  DMA1_Channel1->CNDTR = size; // size of the transfer
//  DMA1_Channel1->CPAR  = srcAdd; // adress of the peripheral
//  DMA1_Channel1->CMAR  = destAdd; // adress of the source
//  DMA1_Channel1->CCR  |= (1<<0); // enable DMA1







//#include <string.h>
//#include <stdlib.h>
//#include <stdio.h>
//#include "main.h"

//// the thingies for the HAL drivers
//ADC_HandleTypeDef hadc1;      // ADC1
//DMA_HandleTypeDef hdma_adc1;  // DMA1
//TIM_HandleTypeDef htim6;      // TIM6

//// ADC buffer for samples
//#define ADC_BUF_LEN  512  // using 512 for FFT point??? 
//uint16_t adc_buf[ADC_BUF_LEN];

//// ADC config function using HAL drivers 
//// chat wrote this nobody panic
//void ADC_Config(void)
//{
//    /* 1. Enable clocks */
//    __HAL_RCC_ADC_CLK_ENABLE();
//    __HAL_RCC_DMA1_CLK_ENABLE();
//    __HAL_RCC_GPIOA_CLK_ENABLE();   // why are we using GPIOA -- should look into this
//    __HAL_RCC_TIM6_CLK_ENABLE();

//    /* 2. Configure ADC pin PA0 (ADC1_IN5 example) */
//    // : what if I want to use channel 1 like a sane person and not channel 5
//    // Can probably replace this code withthe GPIO libaries OR 
//    // add the GPIO HAL driver but def a way to do this with GPIO lib, do need to the alt function thing tho feels like a lot of work 
//    GPIO_InitTypeDef gpio = {0};                // creates HAL structure
//    gpio.Pin = GPIO_PIN_0;                      // PA0, ADC channel 5 is connected to PA0
//    gpio.Mode = GPIO_MODE_ANALOG_ADC_CONTROL;   // Analog mode + ADC control over pin
//    gpio.Pull = GPIO_NOPULL;                    // No pull ups/downs
//    HAL_GPIO_Init(GPIOA, &gpio);                // Apply the configuration to GPIOA

//    /* 3. Configure DMA channel */
//    hdma_adc1.Instance = DMA1_Channel1;
//    hdma_adc1.Init.Request = 5U;  // ADC1 request - HARD CODED
//    hdma_adc1.Init.Direction = DMA_PERIPH_TO_MEMORY;
//    hdma_adc1.Init.PeriphInc = DMA_PINC_DISABLE;
//    hdma_adc1.Init.MemInc = DMA_MINC_ENABLE;
//    hdma_adc1.Init.PeriphDataAlignment = DMA_PDATAALIGN_HALFWORD;
//    hdma_adc1.Init.MemDataAlignment = DMA_MDATAALIGN_HALFWORD;
//    hdma_adc1.Init.Mode = DMA_CIRCULAR;
//    hdma_adc1.Init.Priority = DMA_PRIORITY_HIGH;

//    HAL_DMA_Init(&hdma_adc1);
//    __HAL_LINKDMA(&hadc1, DMA_Handle, hdma_adc1);

//    /* 4. Configure ADC */
//    hadc1.Instance = ADC1;
//    hadc1.Init.ClockPrescaler = ADC_CLOCK_ASYNC_DIV1;
//    hadc1.Init.Resolution = ADC_RESOLUTION_12B;
//    hadc1.Init.DataAlign = ADC_DATAALIGN_RIGHT;
//    hadc1.Init.ScanConvMode = ADC_SCAN_DISABLE;
//    hadc1.Init.EOCSelection = ADC_EOC_SINGLE_CONV;
//    hadc1.Init.LowPowerAutoWait = DISABLE;
//    hadc1.Init.ContinuousConvMode = DISABLE;  // IMPORTANT: timer triggers conversions
//    hadc1.Init.ExternalTrigConv = ADC_EXTERNALTRIG_T6_TRGO;
//    hadc1.Init.ExternalTrigConvEdge = ADC_EXTERNALTRIGCONVEDGE_RISING;
//    hadc1.Init.DMAContinuousRequests = ENABLE;

//    HAL_ADC_Init(&hadc1);

//    /* 5. Configure ADC channel */
//    ADC_ChannelConfTypeDef sConfig = {0};
//    sConfig.Channel = ADC_CHANNEL_5;   // PA0
//    sConfig.Rank = ADC_REGULAR_RANK_1;
//    sConfig.SamplingTime = ADC_SAMPLETIME_12CYCLES_5;
//    HAL_ADC_ConfigChannel(&hadc1, &sConfig);

//    /* 6. Timer 6 @ 48 kHz TRGO */
//    // TIM6 runs from APB1 @ 80 MHz assumed
//    htim6.Instance = TIM6;
//    htim6.Init.Prescaler = 79;    // 80MHz/80 = 1MHz
//    htim6.Init.Period = 1000000/48000 - 1;  // =20-1 => 48 kHz
//    htim6.Init.CounterMode = TIM_COUNTERMODE_UP;
//    HAL_TIM_Base_Init(&htim6);

//    // Set TRGO on update event
//    TIM_MasterConfigTypeDef master = {0};
//    master.MasterOutputTrigger = TIM_TRGO_UPDATE;
//    master.MasterSlaveMode = TIM_MASTERSLAVEMODE_DISABLE;
//    HAL_TIMEx_MasterConfigSynchronization(&htim6, &master);

//    /* 7. Start peripherals */
//    HAL_ADCEx_Calibration_Start(&hadc1, ADC_SINGLE_ENDED);
//    HAL_TIM_Base_Start(&htim6);
    
//    HAL_ADC_Start_DMA(&hadc1, (uint32_t*)adc_buf, ADC_BUF_LEN);
//}

//void SystemClock_Config(void)
//{
//    RCC_OscInitTypeDef RCC_OscInitStruct = {0};
//    RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

//    /** Configure LSE Drive Capability **/
//    HAL_PWR_EnableBkUpAccess();
//    __HAL_RCC_LSEDRIVE_CONFIG(RCC_LSEDRIVE_LOW);

//    /** Initializes the CPU, AHB and APB busses clocks **/
//    RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_MSI;
//    RCC_OscInitStruct.MSIState = RCC_MSI_ON;
//    RCC_OscInitStruct.MSIClockRange = RCC_MSIRANGE_6;   // 4 MHz
//    RCC_OscInitStruct.MSICalibrationValue = RCC_MSICALIBRATION_DEFAULT;
//    RCC_OscInitStruct.PLL.PLLState = RCC_PLL_ON;
//    RCC_OscInitStruct.PLL.PLLSource = RCC_PLLSOURCE_MSI;
//    RCC_OscInitStruct.PLL.PLLM = 1;
//    RCC_OscInitStruct.PLL.PLLN = 40;     // VCO = 4MHz * 40 = 160MHz
//    RCC_OscInitStruct.PLL.PLLR = RCC_PLLR_DIV2; // SYSCLK = 160 / 2 = 80MHz
//    RCC_OscInitStruct.PLL.PLLQ = RCC_PLLQ_DIV2;
//    RCC_OscInitStruct.PLL.PLLP = RCC_PLLP_DIV7;

//    if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK)
//    {
//        while(1); // trap if failed
//    }

//    /** Initializes the CPU, AHB and APB busses clocks **/
//    RCC_ClkInitStruct.ClockType = RCC_CLOCKTYPE_SYSCLK|
//                                  RCC_CLOCKTYPE_HCLK|
//                                  RCC_CLOCKTYPE_PCLK1|
//                                  RCC_CLOCKTYPE_PCLK2;

//    RCC_ClkInitStruct.SYSCLKSource = RCC_SYSCLKSOURCE_PLLCLK;
//    RCC_ClkInitStruct.AHBCLKDivider = RCC_SYSCLK_DIV1;   // 80 MHz
//    RCC_ClkInitStruct.APB1CLKDivider = RCC_HCLK_DIV1;    // 80 MHz
//    RCC_ClkInitStruct.APB2CLKDivider = RCC_HCLK_DIV1;    // 80 MHz

//    if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_4) != HAL_OK)
//    {
//        while(1);
//    }
//}



//int main(void)
//{
//    HAL_Init();
//    SystemClock_Config();
//    ADC_Config();

//    HAL_Delay(100);  // allow DMA to fill the buffer once

//    while (1)
//    {
//        for (int i = 0; i < 32; i++)
//            printf("%u ", adc_buf[i]);

//        printf("\n");
//        // printf("DMA: %lu\n", HAL_ADC_GetError(&hadc1));


//        HAL_Delay(100);
//        printf("adc[0]=%u, DMAerr=%lu\n", adc_buf[0], HAL_ADC_GetError(&hadc1));

//    }
//}

