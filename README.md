# Protokół komunikacyjny

## Dokumentacja
[RF230](http://www.atmel.com/dyn/resources/prod_documents/doc5131.pdf)

## Flagi kompilacji
#### Sterowanie macą nadawania


0 =  3.0 dBm  
1 =  2.6 dBm  
2 =  2.1 dBm  
3 =  1.6 dBm  
4 =  1.1 dBm  
5 =  0.5 dBm  
6 = -0.2 dBm  
7 = -1.2 dBm  
8 = -2.2 dBm  
9 = -3.2 dBm  
10 = -4.2 dBm  
11 = -5.2 dBm  
12 = -7.2 dBm  
13 = -9.2 dBm  
14 = -12.2dBm  
15 = -17.2dBm  
```
PFLAGS+=-DRF230_DEF_RFPOWER=10
```
#### Biblioteka printf
Aby móc skorzystać z funkcji printf należy dodać:
```
CFLAGS += -I$(TINYOS_OS_DIR)/lib/printf
CFLAGS += -DNEW_PRINTF_SEMANTICS # Aby ukryć warningi
```
Nasłuchiwanie na pc:   
```java net.tinyos.tools.PrintfClient -comm serial@/dev/ttyUSB[numer_portu]:iris```
#### Kanał radia
(niesprawdzone)
```
CFLAGS += -DRF230_DEF_CHANNEL= [11-26]
```

#### Długość pakietu
(niesprawdzone)
```
CFLAGS += -DTOSH_DATA_LENGTH=$(PACKETLENGTH)
```

