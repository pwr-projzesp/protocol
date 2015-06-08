#include "ProtocolC.h"
//#include "//printf.h"

module ProtocolC
{
    uses
    {
        interface Boot;
        interface Leds;
        interface Receive as ReceiveREQ;
        interface Timer<TMilli> as Timer;
        interface Timer<TMilli> as RRQTimer;
        interface Timer<TMilli> as ACKTimer;
        interface Timer<TMilli> as TracingTimer;
        interface AMSend;
        interface Packet;
        interface Packet as SerialPacket;
        interface SplitControl as AMControl;
        interface PacketField<uint8_t> as PacketLinkQuality;
        interface PacketField<uint8_t> as PacketRSSI;
        interface Receive as ReceiveSerial;
        interface AMSend as SendSerial;
        interface SplitControl as SerialControl;
    }
}

implementation
{
    message_t packet;
    message_t serial_packet;

    bool pending_rrq = FALSE;
    nx_uint16_t pending_rrq_seq_id;
    nx_uint16_t pending_rrq_dest;
    bool pending_rrq_flush = FALSE;

    bool pending_ack = FALSE;
    nx_uint16_t pending_ack_seq_id;
    nx_uint16_t pending_ack_src;

    bool pending_acks[PROTOCOL_MAX_MOTE_ID];
    bool send_null = FALSE;

    nx_uint16_t curr_seq_id[PROTOCOL_MAX_MOTE_ID];
    nx_uint16_t own_seq_id;
    uint8_t target = 2;

    bool tracing_finished = TRUE;
    nx_uint16_t traced_target;
    nx_uint16_t current_ttl;

    uint16_t trace_id = 0;

    routing_entry_t routing_entries[PROTOCOL_MAX_MOTE_ID];

    event void Boot.booted()
    {
        int i;

        call AMControl.start();
        call SerialControl.start();
        own_seq_id = 0;
        traced_target = 1;

        for (i = 0; i < PROTOCOL_MAX_MOTE_ID; ++i)
        {
            curr_seq_id[i] = 0;
            routing_entries[i].seq_id = 0;
            pending_acks[i] = FALSE;
        }
    }

    event void AMControl.startDone(error_t err)
    {
        if (err == SUCCESS)
        {
            call Timer.startPeriodic(450);
            call TracingTimer.startPeriodic(1663);
        }
        else
        {
            call AMControl.start();
        }
    }

    event void AMControl.stopDone(error_t err)
    {
    }

    event void SerialControl.startDone(error_t err)
    {
        if (err == SUCCESS)
        {
        }
        else
        {
            call SerialControl.start();
        }
    }

    event void SerialControl.stopDone(error_t err)
    {
    }

    void setup_pending_ack(nx_uint16_t seq_id, nx_uint16_t src)
    {
        pending_acks[src] = TRUE;
        call ACKTimer.startOneShot(250);
    }

    void send_message(nx_uint16_t seq_id, nx_uint16_t dest, nx_uint16_t cmd, nx_uint16_t data1, nx_uint16_t data2, nx_uint16_t data3)
    {
        int i;
        protocol_message_t protomsg;
        uint8_t * ptr = (uint8_t *)&protomsg;

        protomsg.seq_id = seq_id;
        protomsg.src = TOS_NODE_ID;
        protomsg.dest = dest;
        protomsg.cmd = cmd;
        protomsg.data1 = data1;
        protomsg.data2 = data2;
        protomsg.data3 = data3;

        for (i = 0; i < sizeof(protocol_message_t); ++i)
        {
            packet.data[i] = ptr[i];
        }

        call AMSend.send(AM_BROADCAST_ADDR, &packet, sizeof(protocol_message_t));

        if (!is_routing_command(cmd) && cmd != PROTOCOL_CMD_ACK)
        {
            setup_pending_ack(seq_id, dest);
        }
    }

    void send_ack(nx_uint16_t seq_id, nx_uint16_t src)
    {
        //printf(" sending ack, seq_id: %d, dest: %d\n", seq_id, src);
        //printfflush();
        send_message(seq_id, src, PROTOCOL_CMD_ACK, 0, 0, 0);
    }

    void send_ack_delayed(nx_uint16_t seq_id, nx_uint16_t src)
    {
        if (!pending_ack)
        {
            pending_ack = TRUE;
            pending_ack_seq_id = seq_id;
            pending_ack_src = src;
        }
    }

    void send_trc(nx_uint16_t seq_id, nx_uint16_t next, nx_uint16_t dest, nx_uint16_t source, nx_uint16_t ttl)
    {
        //printf(" sending trc, seq_id: %d, dest: %d, ttl: %d\n", seq_id, dest, ttl);
        //printfflush();
        send_message(seq_id, next, PROTOCOL_CMD_TRC, dest, source, ttl);
    }

    void send_trr(nx_uint16_t seq_id, nx_uint16_t next, nx_uint16_t dest)
    {
        //printf(" sending trr, seq_id: %d, dest: %d\n", seq_id, dest);
        //printfflush();
        send_message(seq_id, next, PROTOCOL_CMD_TRR, dest, TOS_NODE_ID, 0);
    }

    void send_rrq_reply(nx_uint16_t seq_id, nx_uint16_t dest)
    {
        //printf(" sending rrq reply, seq_id: %d, dest: %d\n", seq_id, dest);
        //printfflush();
        send_message(seq_id, dest, PROTOCOL_CMD_RRR, TOS_NODE_ID, 0, 0);
    }

    void send_routing_request(nx_uint16_t seq_id, nx_uint16_t dest, bool flush)
    {
        //printf(" seding rrq, seq_id: %d, dest: %d\n", seq_id, dest);
        //printfflush();
        call Leds.led1Toggle();

        send_message(seq_id, 0, PROTOCOL_CMD_RRQ, dest, flush, 0);
    }

    void send_routing_request_delayed(nx_uint16_t seq_id, nx_uint16_t dest, bool flush)
    {
        if (!pending_rrq && !routing_entries[dest].seq_id)
        {
            pending_rrq = TRUE;
            pending_rrq_seq_id = seq_id;
            pending_rrq_dest = dest;
            pending_rrq_flush = flush;

            call RRQTimer.startOneShot(50);
        }
    }

    void send_routing_reply(nx_uint16_t seq_id, nx_uint16_t dest, nx_uint16_t src, nx_uint16_t hops)
    {
        //printf(" sending routing reply, seq_id: %d, dest: %d, src: %d, hops: %d\n", seq_id, dest, src, hops);
        //printfflush();
        send_message(seq_id, dest, PROTOCOL_CMD_RRR, src, hops, 0);
    }

    event void AMSend.sendDone(message_t * msg, error_t err)
    {
        if (pending_ack)
        {
            send_ack(pending_ack_seq_id, pending_ack_src);
            pending_ack = FALSE;
        }
    }

    event message_t * ReceiveSerial.receive(message_t * msg, void * payload, uint8_t len)
    {
        return msg;
    }

    event message_t * ReceiveREQ.receive(message_t * msg, void * payload, uint8_t len)
    {
        protocol_message_t * protomsg;

        if (call PacketRSSI.get(msg) < 2)
        {
            return msg;
        }

        protomsg = (protocol_message_t *)msg->data;

        if (!routing_entries[protomsg->src].seq_id || routing_entries[protomsg->src].hops)
        {
            //printf(" saving route to %d\n", protomsg->src);
            routing_entries[protomsg->src].seq_id = protomsg->seq_id;
            routing_entries[protomsg->src].next = protomsg->src;
            routing_entries[protomsg->src].hops = 0;
        }

        if (pending_rrq_dest == protomsg->src)
        {
            pending_rrq = FALSE;
        }

        switch (protomsg->cmd)
        {
        case PROTOCOL_CMD_LED:
        case PROTOCOL_CMD_TRC:
        case PROTOCOL_CMD_TRR:
            if (protomsg->dest == TOS_NODE_ID)
            {
                if (protomsg->cmd == PROTOCOL_CMD_TRC && (protomsg->data1 == TOS_NODE_ID || protomsg->data3 == 0))
                {
                    send_trr(++own_seq_id, routing_entries[protomsg->data2].next, protomsg->data2);
                    send_ack_delayed(protomsg->seq_id, protomsg->src);
                }

                else if (protomsg->data1 == TOS_NODE_ID && protomsg->cmd == PROTOCOL_CMD_LED)
                {
                    call Leds.led0Toggle();
                    send_ack(protomsg->seq_id, protomsg->src);
                }

                else if (protomsg->data1 == TOS_NODE_ID && protomsg->cmd == PROTOCOL_CMD_TRR)
                {
                    serial_packet.data[0] = 0x01;
                    *(uint16_t *)(serial_packet.data + 1) = trace_id;
                    *(uint16_t *)(serial_packet.data + 3) = protomsg->data2;
                    serial_packet.data[5] = 0x00;
                    call SendSerial.send(AM_BROADCAST_ADDR, &serial_packet, 5);

                    //printf(" got trr: %d\n", protomsg->data2);
                    //printfflush();

                    if (protomsg->data2 == traced_target)
                    {
                        tracing_finished = TRUE;
                        send_null = TRUE;
                        send_ack(protomsg->seq_id, protomsg->src);
                    }
                    else
                    {
                        if (routing_entries[traced_target].seq_id)
                        {
                            send_trc(++own_seq_id, routing_entries[traced_target].next, traced_target, TOS_NODE_ID, ++current_ttl);
                            send_ack_delayed(protomsg->seq_id, protomsg->src);
                        }
                        else
                        {
                            send_null = TRUE;

                            //printf(" cannot send trc - route dead\n");
                            //printfflush();

                            tracing_finished = TRUE;
                        }
                    }
                }

                // ...the message came back...
                else if (protomsg->data2 == TOS_NODE_ID && protomsg->cmd == PROTOCOL_CMD_LED)
                {
                    routing_entries[protomsg->data1].seq_id = 0;
                    send_routing_request(++own_seq_id, protomsg->data1, TRUE);
                }

                else if (protomsg->seq_id > curr_seq_id[protomsg->data2])
                {
                    curr_seq_id[protomsg->data2] = protomsg->seq_id;
                    call Leds.led2Toggle();

                    if (routing_entries[protomsg->data1].seq_id)
                    {
                        if (protomsg->cmd == PROTOCOL_CMD_TRC)
                        {
                            --protomsg->data3;
                        }
                        send_message(protomsg->seq_id, routing_entries[protomsg->data1].next, protomsg->cmd, protomsg->data1, protomsg->data2, protomsg->data3);
                        send_ack_delayed(protomsg->seq_id, protomsg->src);
                    }

                    else
                    {
                        send_routing_request(++own_seq_id, protomsg->data1, FALSE);
                    }
                }
            }

            else if (protomsg->data1 == TOS_NODE_ID)
            {
                send_routing_request(++own_seq_id, protomsg->src, FALSE);
            }

            break;

        case PROTOCOL_CMD_ACK:
            //printf(" got ACK, seq_id: %d, from %d to %d\n", protomsg->seq_id, protomsg->src, protomsg->dest);
            //printfflush();

            if (protomsg->dest == TOS_NODE_ID)
            {
                pending_acks[protomsg->src] = FALSE;
            }

            break;

        case PROTOCOL_CMD_RRQ:
            //printf(" got RRQ, seq_id: %d, from %d to %d\n", protomsg->seq_id, protomsg->src, protomsg->data1);

            if (protomsg->data2)
            {
                routing_entries[protomsg->data1].seq_id = 0;
            }

            if (protomsg->data1 == TOS_NODE_ID)
            {
                send_rrq_reply(protomsg->seq_id, protomsg->src);
            }

            else if (routing_entries[protomsg->data1].seq_id)
            {
                send_routing_reply(protomsg->seq_id, protomsg->src, protomsg->data1, routing_entries[protomsg->data1].hops + 1);
            }

            else
            {
                send_routing_request_delayed(protomsg->seq_id, protomsg->data1, 0);
            }

            break;

        case PROTOCOL_CMD_RRR:
            //printf(" got RRR, seq_id: %d, from %d via %d, hops: %d\n", protomsg->seq_id, protomsg->data1, protomsg->src, protomsg->data2);
            if (protomsg->data1 == TOS_NODE_ID)
            {
                break;
            }

            if (pending_rrq && pending_rrq_seq_id == protomsg->seq_id && pending_rrq_dest == protomsg->src)
            {
                pending_rrq = FALSE;
            }

            if (!routing_entries[protomsg->data1].seq_id || routing_entries[protomsg->data1].hops > protomsg->data2)
            {
                routing_entries[protomsg->data1].seq_id = protomsg->seq_id;
                routing_entries[protomsg->data1].next = protomsg->src;
                routing_entries[protomsg->data1].hops = protomsg->data2;
            }

            break;
        }

        //printfflush();

        return msg;
    }

    event void Timer.fired()
    {
        if (TOS_NODE_ID == 1)
        {
            if (routing_entries[target].seq_id)
            {
                //printf(" sending LED to %d via %d\n", target, routing_entries[target].next);
                //printfflush();

                send_message(++own_seq_id, routing_entries[target].next, PROTOCOL_CMD_LED, target, TOS_NODE_ID, 0);
                call Leds.led2Toggle();
            }

            else
            {
                send_routing_request(++own_seq_id, target, FALSE);
            }

            if (++target == 4)
            {
                target = 2;
            }
        }
    }

    event void RRQTimer.fired()
    {
        if (pending_rrq)
        {
            pending_rrq = FALSE;
            send_routing_request(pending_rrq_seq_id, pending_rrq_dest, pending_rrq_flush);
        }
    }

    event void ACKTimer.fired()
    {
        int i;
        for (i = 0; i < PROTOCOL_MAX_MOTE_ID; ++i)
        {
            if (pending_acks[i])
            {
                //printf(" forgetting route to %d\n", i);
                //printfflush();

                pending_acks[i] = FALSE;
                routing_entries[i].seq_id = 0;
                send_routing_request_delayed(++own_seq_id, i, TRUE);
                break;
            }
        }
    }

    event void SendSerial.sendDone(message_t *, error_t)
    {
        if (send_null)
        {
            send_null = FALSE;
            serial_packet.data[0] = 0x01;
            *(uint16_t *)(serial_packet.data + 1) = trace_id;
            *(uint16_t *)(serial_packet.data + 3) = 0x0000;
            serial_packet.data[5] = 0x00;
            call SendSerial.send(AM_BROADCAST_ADDR, &serial_packet, 5);
        }
    }

    event void TracingTimer.fired()
    {
        if (TOS_NODE_ID != 1)
        {
            return;
        }

        if (!tracing_finished)
        {
            serial_packet.data[0] = 0x01;
            *(uint16_t *)(serial_packet.data + 1) = trace_id;
            *(uint16_t *)(serial_packet.data + 3) = 0x00;
            call SendSerial.send(AM_BROADCAST_ADDR, &serial_packet, 5);

            //printf(" aborting trc\n");
            //printfflush();

            routing_entries[traced_target].seq_id = 0;

            tracing_finished = TRUE;
        }

        tracing_finished = FALSE;
        current_ttl = 0;
        if (++traced_target == 4)
        {
            traced_target = 2;
        }

        if (routing_entries[traced_target].seq_id)
        {
            ++trace_id;
            send_trc(++own_seq_id, routing_entries[traced_target].next, traced_target, TOS_NODE_ID, current_ttl);
        }
        else
        {
            send_routing_request(++own_seq_id, traced_target, FALSE);
            tracing_finished = TRUE;
        }
    }
}

