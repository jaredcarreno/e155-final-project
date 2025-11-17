/**
    Main Header: Contains general defines and selected portions of CMSIS files
    @file main.h
    @author Josh Brake
    @version 1.0 10/7/2020
*/

#ifndef MAIN_H
#define MAIN_H

// need to include all libraries [only need to add header files] here
#include "C:\e155-project\e155-final-project\mcu\lib\Drivers\Inc\stm32l4xx_hal.h"
//#include "STM32L432KC_FLASH.h"
//#include "STM32L432KC_GPIO.h"
//#include "STM32L432KC_RCC.h"
//#include "STM32L432KC_SPI.h"
//#include "STM32L432KC_TIM.h"
//#include "STM32L432KC_USART.h"
#include "STM32L432KC.h"

#define LED_PIN PA6 // LED pin for blinking on Port B pin 3
#define BUFF_LEN 32

#endif // MAIN_H