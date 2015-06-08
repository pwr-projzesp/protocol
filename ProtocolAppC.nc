configuration ProtocolAppC
{
}
implementation
{
    components RF230ActiveMessageC;
    components SerialActiveMessageC;

    components MainC;
    components ProtocolC as Proto;
    components LedsC;
    //components PrintfC;
    components SerialStartC;

    components new AMSenderC(6) as Sender;
    components new AMReceiverC(6) as Receiver;

    components new TimerMilliC() as Timer;
    components new TimerMilliC() as RRQTimer;
    components new TimerMilliC() as ACKTimer;
    components new TimerMilliC() as TracingTimer;

    Proto.Boot -> MainC.Boot;
    Proto.AMSend -> Sender;
    Proto.ReceiveREQ -> Receiver;
    Proto.Packet -> Sender;
    Proto.AMControl -> RF230ActiveMessageC;
    Proto.Timer -> Timer;
    Proto.RRQTimer -> RRQTimer;
    Proto.ACKTimer -> ACKTimer;
    Proto.TracingTimer -> TracingTimer;
    Proto.Leds -> LedsC;
    Proto.PacketLinkQuality -> RF230ActiveMessageC.PacketLinkQuality;
    Proto.PacketRSSI -> RF230ActiveMessageC.PacketRSSI;
    Proto.ReceiveSerial -> SerialActiveMessageC.Receive[0];
    Proto.SendSerial -> SerialActiveMessageC.AMSend[0];
    Proto.SerialControl -> SerialActiveMessageC;
    Proto.SerialPacket -> SerialActiveMessageC;
}

