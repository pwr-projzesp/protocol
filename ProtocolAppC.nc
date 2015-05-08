configuration ProtocolAppC
{
}
implementation
{
    components MainC;
    components ProtocolC as Proto;
    components LedsC;
    components PrintfC;
    components SerialStartC;

    components new AMSenderC(6) as Sender;
    components new AMReceiverC(6) as Receiver;
    components ActiveMessageC;

    components new TimerMilliC() as Timer;
    components new TimerMilliC() as RRQTimer;
    components new TimerMilliC() as ACKTimer;

    Proto.Boot -> MainC.Boot;
    Proto.AMSend -> Sender;
    Proto.ReceiveREQ -> Receiver;
    Proto.Packet -> Sender;
    Proto.AMControl -> ActiveMessageC;
    Proto.Timer -> Timer;
    Proto.RRQTimer -> RRQTimer;
    Proto.ACKTimer -> ACKTimer;
    Proto.Leds -> LedsC;
}

