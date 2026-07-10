namespace flybrain {
    // what i want to do here is to make a pub-sub bus system internally that is statically checked.

    // what I want to be able to do is to register topics with types just like what can be done within ROS 
    // however I want to be able statically enforce that every channel has exactly 1 writer

    struct ChannelRegistry {

    };
    
    class BusChannel {
        
        public:

    };

    // a channel can only have one publisher ever
    class ChannelPublisher {

        public:
            ChannelPublisher();
    };
}