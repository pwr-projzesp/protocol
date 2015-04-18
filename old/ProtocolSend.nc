interface ProtocolSend
{
    command error_t send(uint8_t address, message_t * message, uint8_t length);
    event void send_done(message_t * msg, error_t success);
}

