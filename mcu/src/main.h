/**
    Main Header: Contains general defines and selected portions of CMSIS files
    @file main.h
    @author Josh Brake
    @version 1.0 10/7/2020
*/

#ifndef MAIN_H
#define MAIN_H

// need to include all libraries [only need to add header files] here
#include "STM32L432KC_FLASH.h"
#include "STM32L432KC_GPIO.h"
#include "STM32L432KC_RCC.h"
#include "STM32L432KC_SPI.h"
#include "STM32L432KC_TIM.h"
#include "STM32L432KC_USART.h"
#include "STM32L432KC.h"
#include "stm32l432xx.h" 
#include "STM32L432KC_DAC60501.h"
#include "STM32L432KC_ADC.h"
#include "STM32L432KC_DMA.h"
#include "signal_processing.h"


#define LED_PIN PA6 // LED pin for blinking on Port B pin 3
#define BUFF_LEN 32

#endif // MAIN_H