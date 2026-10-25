/*!
  * @file ModbeeGP8XXX.cpp
  * @brief GP8XXX series DAC driver library (GP8101, GP8101S, GP8211S, GP8413, GP8501, GP8503, GP8512, GP8403, GP8302 driver method is implemented)
  * @copyright   Copyright (c) 2010 DFRobot Co.Ltd (http://www.dfrobot.com)
  * @license     The MIT License (MIT)
  * @author      [fary](feng.yang@dfrobot.com)
  * @version  V1.0
  * @date  2023-05-10
  * @url https://github.com/DFRobot/DFRobot_GP8XXX
  */
 
  #include "ModbeeGP8XXX.h"

  int ModbeeGP8XXX_IIC::begin(void)
  {
    _pWire->begin();
    _pWire->beginTransmission(_deviceAddr);
    return _pWire->endTransmission();
  }
  
  void ModbeeGP8XXX_IIC::setDACOutRange(eOutPutRange_t range)
  {
    uint8_t data=0x00;
    switch(range){
      case eOutputRange5V:    
        writeRegister(GP8XXX_CONFIG_CURRENT_REG>>1,&data,1);
        break;
      case eOutputRange10V:  
        data=0x11;
        writeRegister(GP8XXX_CONFIG_CURRENT_REG>>1,&data,1);
        break;
      default:
        break;
    }
  }
  
  void ModbeeGP8XXX_IIC::setDACOutVoltage(uint16_t voltage, uint8_t channel)
  {
    if(voltage > _resolution)
      voltage = _resolution;
      
    if(_resolution == RESOLUTION_12_BIT ){
      voltage = voltage << 4;
    }else if(_resolution == RESOLUTION_15_BIT) {
      voltage = voltage << 1;
    }
    sendData(voltage, channel);
  }
  
  void ModbeeGP8512::setDACOutVoltage(uint16_t voltage, uint8_t channel)
  {
    if(voltage > _resolution)
      voltage = _resolution;
    sendData(voltage, channel);
  }
  
  void ModbeeGP8XXX_IIC::sendData(uint16_t data, uint8_t channel)
  {
    uint8_t buff[4]={ uint8_t(data & 0xff) , uint8_t(data >> 8) , uint8_t(data & 0xff) , uint8_t(data >> 8)};
    if(channel == 0){
      writeRegister(GP8XXX_CONFIG_CURRENT_REG,(void *)buff,2);
    }else if(channel == 1){
      writeRegister(GP8XXX_CONFIG_CURRENT_REG<<1,(void *)buff,2);
    }else if(channel == 2){
      writeRegister(GP8XXX_CONFIG_CURRENT_REG,(void *)buff,4);
    }
  }
  
  uint8_t ModbeeGP8XXX_IIC::writeRegister(uint8_t reg, void* pBuf, size_t size)
  {
    if(pBuf == NULL){
        return 1;
    }
    uint8_t * _pBuf = (uint8_t *)pBuf;
    _pWire->beginTransmission(_deviceAddr);
    _pWire->write(reg);
    for( uint16_t i = 0; i < size; i++ ){
      _pWire->write(_pBuf[i]);
    }
    _pWire->endTransmission();
  
    return 0;
  }
  
  void ModbeeGP8XXX_IIC::store(void)
  {
    static int step = 0;
    static unsigned long stepStart = 0;
    static int byteCount = 0;
    
    switch(step) {
      case 0:
        #if defined(ESP32)
          _pWire->~TwoWire();
        #elif !defined(ESP8266)
          _pWire->end();
        #endif
        
        pinMode(_scl, OUTPUT);
        pinMode(_sda, OUTPUT);
        digitalWrite(_scl, HIGH);
        digitalWrite(_sda, HIGH);
        step = 1;
        return;
        
      case 1:
        // First startSignal
        startSignal();
        step = 2;
        return;
        
      case 2:
        // Send timing head (3 bits)
        if (sendByte(GP8XXX_STORE_TIMING_HEAD, 0, 3, false) == 0) return;
        step = 3;
        return;
        
      case 3:
        // First stopSignal
        stopSignal();
        step = 4;
        return;
        
      case 4:
        // Second startSignal
        startSignal();
        step = 5;
        return;
        
      case 5:
        // Send timing address
        if (sendByte(GP8XXX_STORE_TIMING_ADDR, 0) == 0) return;
        step = 6;
        return;
        
      case 6:
        // Send timing command 1
        if (sendByte(GP8XXX_STORE_TIMING_CMD1, 0) == 0) return;
        step = 7;
        return;
        
      case 7:
        // Second stopSignal
        stopSignal();
        step = 8;
        return;
        
      case 8:
        // Third startSignal
        startSignal();
        step = 9;
        return;
        
      case 9:
        // Send device address
        if (sendByte(_deviceAddr<<1, 1) == 0) return;
        byteCount = 0;
        step = 10;
        return;
        
      case 10:
        // Send 8 bytes of GP8XXX_STORE_TIMING_CMD2
        if (sendByte(GP8XXX_STORE_TIMING_CMD2, 1) == 0) return;
        byteCount++;
        if (byteCount < 8) {
          return; // Send next byte
        }
        step = 11;
        return;
        
      case 11:
        // Third stopSignal
        stopSignal();
        stepStart = millis();
        step = 12;
        return;
        
      case 12:
        // 10ms delay
        if ((millis() - stepStart) < GP8XXX_STORE_TIMING_DELAY) return;
        step = 13;
        return;
        
      case 13:
        // Fourth startSignal
        startSignal();
        step = 14;
        return;
        
      case 14:
        // Send timing head again (3 bits)
        if (sendByte(GP8XXX_STORE_TIMING_HEAD, 0, 3, false) == 0) return;
        step = 15;
        return;
        
      case 15:
        // Fourth stopSignal
        stopSignal();
        step = 16;
        return;
        
      case 16:
        // Fifth startSignal
        startSignal();
        step = 17;
        return;
        
      case 17:
        // Send timing address
        if (sendByte(GP8XXX_STORE_TIMING_ADDR) == 0) return;
        step = 18;
        return;
        
      case 18:
        // Send timing command 2
        if (sendByte(GP8XXX_STORE_TIMING_CMD2) == 0) return;
        step = 19;
        return;
        
      case 19:
        // Final stopSignal
        stopSignal();
        step = 20;
        return;
        
      case 20:
        // Restart Wire
        _pWire->begin();
        step = 0; // Reset for next call
        break;
    }
  }
  
  void ModbeeGP8XXX_IIC::startSignal(void)
  {
    static int step = 0;
    static unsigned long stepStart = 0;
    
    switch(step) {
      case 0:
        digitalWrite(_scl,HIGH);
        digitalWrite(_sda,HIGH);
        stepStart = micros();
        step = 1;
        return;
        
      case 1:
        if ((micros() - stepStart) < I2C_CYCLE_BEFORE) return;
        digitalWrite(_sda,LOW);
        stepStart = micros();
        step = 2;
        return;
        
      case 2:
        if ((micros() - stepStart) < I2C_CYCLE_AFTER) return;
        digitalWrite(_scl,LOW);
        stepStart = micros();
        step = 3;
        return;
        
      case 3:
        if ((micros() - stepStart) < I2C_CYCLE_TOTAL) return;
        step = 0; // Reset for next call
        break;
    }
  }
  
  void ModbeeGP8XXX_IIC::stopSignal(void)
  {
    static int step = 0;
    static unsigned long stepStart = 0;
    
    switch(step) {
      case 0:
        digitalWrite(_sda,LOW);
        stepStart = micros();
        step = 1;
        return;
        
      case 1:
        if ((micros() - stepStart) < I2C_CYCLE_BEFORE) return;
        digitalWrite(_scl,HIGH);
        stepStart = micros();
        step = 2;
        return;
        
      case 2:
        if ((micros() - stepStart) < I2C_CYCLE_TOTAL) return;
        digitalWrite(_sda,HIGH);
        stepStart = micros();
        step = 3;
        return;
        
      case 3:
        if ((micros() - stepStart) < I2C_CYCLE_TOTAL) return;
        step = 0; // Reset for next call
        break;
    }
  }
  
  uint8_t ModbeeGP8XXX_IIC::sendByte(uint8_t data, uint8_t ack, uint8_t bits, bool flag)
  {
    static int bitIndex = -1;
    static int step = 0;
    static unsigned long stepStart = 0;
    static uint8_t currentData = 0;
    static uint8_t currentAck = 0;
    static uint8_t currentBits = 8;
    static bool currentFlag = true;
    
    if (bitIndex == -1) {
      // Initialize for new byte
      currentData = data;
      currentAck = ack;
      currentBits = bits;
      currentFlag = flag;
      bitIndex = bits - 1;
      step = 0;
    }
    
    if (bitIndex >= 0) {
      switch(step) {
        case 0:
          if(currentData & (1<<bitIndex)){
            digitalWrite(_sda,HIGH);
          }else{
            digitalWrite(_sda,LOW);
          }
          stepStart = micros();
          step = 1;
          return 0; // Not complete
          
        case 1:
          if ((micros() - stepStart) < I2C_CYCLE_BEFORE) return 0;
          digitalWrite(_scl,HIGH);
          stepStart = micros();
          step = 2;
          return 0;
          
        case 2:
          if ((micros() - stepStart) < I2C_CYCLE_TOTAL) return 0;
          digitalWrite(_scl,LOW);
          stepStart = micros();
          step = 3;
          return 0;
          
        case 3:
          if ((micros() - stepStart) < I2C_CYCLE_AFTER) return 0;
          bitIndex--;
          step = 0;
          return 0; // Continue with next bit
      }
    }
    
    // All bits sent - handle ACK
    if(currentFlag) {
      uint8_t ackResult = recvAck(currentAck);
      if (ackResult == 0) return 0; // Still processing ACK
      bitIndex = -1; // Reset for next call
      return ackResult;
    } else {
      digitalWrite(_sda,LOW);
      digitalWrite(_scl,HIGH);
      bitIndex = -1; // Reset for next call
      return 1; // Complete
    }
  }
  
  uint8_t ModbeeGP8XXX_IIC::recvAck(uint8_t ack)
  {
    static int step = 0;
    static unsigned long stepStart = 0;
    static uint16_t errorTime = 0;
    static uint8_t ack_ = 0;
    static uint8_t expectedAck = 0;
    
    if (step == 0) {
      expectedAck = ack;
    }
    
    switch(step) {
      case 0:
        pinMode(_sda,INPUT_PULLUP);
        digitalWrite(_sda,HIGH);
        stepStart = micros();
        step = 1;
        return 0; // Not complete
        
      case 1:
        if ((micros() - stepStart) < I2C_CYCLE_BEFORE) return 0;
        digitalWrite(_scl,HIGH);
        stepStart = micros();
        step = 2;
        return 0;
        
      case 2:
        if ((micros() - stepStart) < I2C_CYCLE_AFTER) return 0;
        errorTime = 0;
        stepStart = micros();
        step = 3;
        return 0;
        
      case 3:
        // Check for expected ACK
        if(digitalRead(_sda) == expectedAck) {
          step = 4; // Got ACK, proceed
          return 0;
        }
        
        // Wait 1 microsecond before checking again
        if ((micros() - stepStart) >= 1) {
          errorTime++;
          stepStart = micros();
          if(errorTime > 250) {
            step = 4; // Timeout, proceed anyway
            return 0;
          }
        }
        return 0; // Keep checking
        
      case 4:
        ack_ = digitalRead(_sda);
        stepStart = micros();
        step = 5;
        return 0;
        
      case 5:
        if ((micros() - stepStart) < I2C_CYCLE_BEFORE) return 0;
        digitalWrite(_scl,LOW);
        stepStart = micros();
        step = 6;
        return 0;
        
      case 6:
        if ((micros() - stepStart) < I2C_CYCLE_AFTER) return 0;
        pinMode(_sda,OUTPUT);
        step = 0; // Reset for next call
        return ack_; // Complete - return the ACK value
    }
    
    return 0;
  }
  
  int ModbeeGP8XXX_PWM::begin()
  {
    #if (defined ESP8266)
      analogWriteRange(255);
    #endif  
    if(_pin0 !=-1 ){
      pinMode(_pin0, OUTPUT);
      analogWrite(_pin0,0);
    }
    if(_pin1 !=-1 ){
      pinMode(_pin1, OUTPUT);
      analogWrite(_pin1,0);
    }
    return 0;
  }
  
  void ModbeeGP8XXX_PWM::setDACOutVoltage(uint16_t data , uint8_t channel)
  { 
    sendData(data, channel);
  }
  
  void ModbeeGP8XXX_PWM::sendData(uint8_t data, uint8_t channel)
  {
      if( (channel == 0) && (_pin0 != -1) ){
        analogWrite(_pin0, data);
      }else if( (channel == 1) && (_pin1 != -1) ){
        analogWrite(_pin1, data);
      }else if( (channel == 2) && (_pin0 != -1) && (_pin1 != -1) ){
        analogWrite(_pin0, (uint8_t)data);
          analogWrite(_pin1, (uint8_t)data);
      }
  }