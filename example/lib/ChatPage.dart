import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class ChatPage extends StatefulWidget {
  final BluetoothDevice server;
  
  const ChatPage({this.server});
  
  @override
  _ChatPage createState() => new _ChatPage();
}

class _Message {
  int whom;
  String text;

  _Message(this.whom, this.text);
}

class _ChatPage extends State<ChatPage> {
  static final clientID = 0;
  static final maxMessageLength = 4096 - 3;

  StreamSubscription<Uint8List> _streamSubscription;

  List<_Message> messages = List<_Message>();
  String _messageBuffer = '';

  final TextEditingController textEditingController = new TextEditingController();
  final ScrollController listScrollController = new ScrollController();

  bool isConnecting = true;
  bool get isConnected => _streamSubscription != null;

  @override
  void initState() {
    super.initState();

    FlutterBluetoothSerial.instance.connect(widget.server).then((_) { // @TODO ? shouldn't be done via `.listen()`?
      isConnecting = false;

      // Subscribe for incoming data after connecting
      _streamSubscription = FlutterBluetoothSerial.instance.onRead().listen(_onDataReceived);
      setState(() {/* Update for `isConnecting`, since depends on `_streamSubscription` */});

      // Subscribe for remote disconnection
      _streamSubscription.onDone(() {
        print('we got disconnected by remote!');
        _streamSubscription = null;
        setState(() {/* Update for `isConnected`, since is depends on `_streamSubscription` */});
      });
    });
  }

  @override
  void dispose() {
    // Avoid memory leak (`setState` after dispose) and disconnect
    if (isConnected) {
      _streamSubscription.cancel();
      print('we are disconnecting locally!');
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Row> list = messages.map((_message) {
      return Row(
        children: <Widget>[
          Container(
            child: Text((text) {
              return text == '/shrug' ? '¯\\_(ツ)_/¯' : text;
            } (_message.text.trim()), style: TextStyle(color: Colors.white)),
            padding: EdgeInsets.all(12.0),
            margin: EdgeInsets.only(bottom: 8.0, left: 8.0, right: 8.0),
            width: 222.0,
            decoration: BoxDecoration(color: _message.whom == clientID ? Colors.blueAccent : Colors.grey, borderRadius: BorderRadius.circular(7.0)),
          ),
        ],
        mainAxisAlignment: _message.whom == clientID ? MainAxisAlignment.end : MainAxisAlignment.start,
      );
    }).toList();
    
    return Scaffold(
      appBar: AppBar(
        title: (
          isConnecting ? Text('Connecting chat to ' + widget.server.name + '...') :
          isConnected ? Text('Live chat with ' + widget.server.name) :
          Text('Chat log with ' + widget.server.name)
        )
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Flexible(
              child: ListView(
                padding: const EdgeInsets.all(12.0),
                controller: listScrollController,
                children: list
              )
            ),
            Row(
              children: <Widget>[
                Flexible(
                  child: Container(
                    margin: const EdgeInsets.only(left: 16.0),
                    child: TextField(
                      style: const TextStyle(fontSize: 15.0),
                      controller: textEditingController,
                      decoration: InputDecoration.collapsed(
                        hintText: (
                          isConnecting ? 'Wait until connected...' : 
                          isConnected ? 'Type your message...' : 
                          'Chat got disconnected'
                        ),
                        hintStyle: const TextStyle(color: Colors.grey),
                      ),
                      enabled: isConnected,
                    )
                  )
                ),
                Container(
                  margin: const EdgeInsets.all(8.0),
                  child: IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: isConnected ? () => _sendMessage(textEditingController.text) : null
                  ),
                ),
              ]
            )
          ]
        )
      )
    );
  }

  void _onDataReceived(Uint8List data) {
    // Allocate buffer for parsed data
    int backspacesCounter = 0;
    data.forEach((byte) {
      if (byte == 8 || byte == 127) {
        backspacesCounter++;
      }
    });
    Uint8List buffer = Uint8List(data.length - backspacesCounter);
    int bufferIndex = buffer.length;

    // Apply backspace control character
    backspacesCounter = 0;
    for (int i = data.length - 1; i >= 0; i--) {
      if (data[i] == 8 || data[i] == 127) {
        backspacesCounter++;
      }
      else {
        if (backspacesCounter > 0) {
          backspacesCounter--;
        }
        else {
          buffer[--bufferIndex] = data[i];
        }
      }
    }

    // Create message if there is new line character
    String dataString = String.fromCharCodes(buffer);
    int index = buffer.indexOf(13);
    if (~index != 0) { // \r\n
      setState(() {
        messages.add(_Message(1, 
          backspacesCounter > 0 
            ? _messageBuffer.substring(0, _messageBuffer.length - backspacesCounter) 
            : _messageBuffer
          + dataString.substring(0, index)
        ));
        _messageBuffer = dataString.substring(index);
      });
    }
    else {
      _messageBuffer = (
        backspacesCounter > 0 
          ? _messageBuffer.substring(0, _messageBuffer.length - backspacesCounter) 
          : _messageBuffer
        + dataString
      );
    }
  }

  void _sendMessage(String text) {
    text = text.trim();
    if (text.length > 0)  {
      textEditingController.clear();

      FlutterBluetoothSerial.instance.write(text + "\r\n");

      setState(() {
        messages.add(_Message(clientID, text));
      });

      Future.delayed(Duration(milliseconds: 333)).then((_) {
        listScrollController.animateTo(listScrollController.position.maxScrollExtent, duration: Duration(milliseconds: 333), curve: Curves.easeOut);
      });
    }
  }
}
