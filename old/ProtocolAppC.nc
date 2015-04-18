configuration ProtocolAppC
{
}
implementation
{
    components MainC;
    components ProtocolC as Proto;
    components LedsC;

    components new AMSenderC(6) as Sender;
    components new AMReceiverC(6) as Receiver;
    components ActiveMessageC;

    components new TimerMilliC() as TimeoutTimer;
    components new TimerMilliC() as SendTimer;

    Proto.Boot -> MainC.Boot;
    Proto.AMSend -> Sender;
    Proto.ReceiveREQ -> Receiver;
    Proto.Packet -> Sender;
    Proto.AMControl -> ActiveMessageC;
    Proto.TimeoutTimer -> TimeoutTimer;
    Proto.SendTimer -> SendTimer;
    Proto.Leds -> LedsC;
}
