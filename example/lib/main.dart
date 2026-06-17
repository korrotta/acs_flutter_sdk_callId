import 'package:acs_flutter_sdk/acs_flutter_sdk.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ACS Flutter SDK Demo',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _sdk = AcsFlutterSdk();
  String _platformVersion = 'Unknown';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initPlatformState();
  }

  Future<void> _initPlatformState() async {
    try {
      final version = await _sdk.getPlatformVersion() ?? 'Unknown';
      if (mounted) {
        setState(() => _platformVersion = version);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _platformVersion = 'Error: $e');
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Azure Communication Services'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.person), text: 'Identity'),
            Tab(icon: Icon(Icons.call), text: 'Calling'),
            Tab(icon: Icon(Icons.chat), text: 'Chat'),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.blue.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.info_outline, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Platform: $_platformVersion',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                IdentityTab(sdk: _sdk),
                CallingTab(sdk: _sdk),
                ChatTab(sdk: _sdk),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Identity Tab
class IdentityTab extends StatefulWidget {
  final AcsFlutterSdk sdk;

  const IdentityTab({super.key, required this.sdk});

  @override
  State<IdentityTab> createState() => _IdentityTabState();
}

class _IdentityTabState extends State<IdentityTab> {
  final _connectionStringController = TextEditingController();
  String _status = 'Not initialized';
  bool _isLoading = false;

  @override
  void dispose() {
    _connectionStringController.dispose();
    super.dispose();
  }

  Future<void> _initializeIdentity() async {
    if (_connectionStringController.text.isEmpty) {
      _showError('Please enter a connection string');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final identityClient = widget.sdk.createIdentityClient();
      await identityClient.initialize(_connectionStringController.text);
      setState(() {
        _status = 'Identity client initialized successfully';
        _isLoading = false;
      });
      _showSuccess('Identity client initialized');
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isLoading = false;
      });
      _showError(e.toString());
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Identity Management',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Note: In production, identity operations should be performed server-side for security.',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: Colors.orange,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _connectionStringController,
            decoration: const InputDecoration(
              labelText: 'Connection String',
              hintText: 'Enter your ACS connection string',
              border: OutlineInputBorder(),
              helperText: 'Get this from Azure Portal',
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _initializeIdentity,
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: const Text('Initialize Identity Client'),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Status',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(_status),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Card(
            color: Colors.blue,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Production Best Practices',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Text(
                    '1. Never expose connection strings in client apps\n'
                    '2. Create users and generate tokens on your backend\n'
                    '3. Implement token refresh mechanism\n'
                    '4. Use secure storage for tokens',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Calling Tab
class CallingTab extends StatefulWidget {
  final AcsFlutterSdk sdk;

  const CallingTab({super.key, required this.sdk});

  @override
  State<CallingTab> createState() => _CallingTabState();
}

class _CallingTabState extends State<CallingTab> {
  final _accessTokenController = TextEditingController();
  final _participantController = TextEditingController();
  final _groupCallIdController = TextEditingController();
  final _meetingLinkController = TextEditingController();
  String _status = 'Not initialized';
  bool _isLoading = false;
  bool _isInCall = false;
  bool _isMuted = false;
  bool _isVideoOn = false;
  bool _joinWithVideo = false;
  late AcsCallClient _callClient;

  @override
  void initState() {
    super.initState();
    _callClient = widget.sdk.createCallClient();
  }

  @override
  void dispose() {
    _accessTokenController.dispose();
    _participantController.dispose();
    _groupCallIdController.dispose();
    _meetingLinkController.dispose();
    _callClient.dispose();
    super.dispose();
  }

  Future<void> _initializeCalling() async {
    if (_accessTokenController.text.isEmpty) {
      _showError('Please enter an access token');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _callClient.requestPermissions();
      await _callClient.initialize(_accessTokenController.text);
      setState(() {
        _status = 'Calling client initialized';
        _isLoading = false;
      });
      _showSuccess('Calling client initialized');
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isLoading = false;
      });
      _showError(e.toString());
    }
  }

  Future<void> _startCall() async {
    if (_participantController.text.isEmpty) {
      _showError('Please enter participant ID');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _callClient.startCall([
        _participantController.text,
      ], withVideo: _joinWithVideo);
      setState(() {
        _status = 'Call started';
        _isInCall = true;
        _isVideoOn = _joinWithVideo;
        _isLoading = false;
      });
      _showSuccess('Call started');
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isLoading = false;
      });
      _showError(e.toString());
    }
  }

  Future<void> _joinGroupCall() async {
    if (_groupCallIdController.text.isEmpty) {
      _showError('Please enter a group call ID');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _callClient.joinCall(
        _groupCallIdController.text,
        withVideo: _joinWithVideo,
      );
      setState(() {
        _status = 'Joined group call';
        _isInCall = true;
        _isVideoOn = _joinWithVideo;
        _isLoading = false;
      });
      _showSuccess('Joined group call');
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isLoading = false;
      });
      _showError(e.toString());
    }
  }

  Future<void> _joinTeamsMeeting() async {
    if (_meetingLinkController.text.isEmpty) {
      _showError('Please enter a Teams meeting link');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _callClient.joinTeamsMeeting(
        _meetingLinkController.text,
        withVideo: _joinWithVideo,
      );
      setState(() {
        _status = 'Joined Teams meeting';
        _isInCall = true;
        _isVideoOn = _joinWithVideo;
        _isLoading = false;
      });
      _showSuccess('Joined Teams meeting');
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isLoading = false;
      });
      _showError(e.toString());
    }
  }

  Future<void> _endCall() async {
    setState(() => _isLoading = true);

    try {
      await _callClient.endCall();
      setState(() {
        _status = 'Call ended';
        _isInCall = false;
        _isMuted = false;
        _isVideoOn = false;
        _isLoading = false;
      });
      _showSuccess('Call ended');
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isLoading = false;
      });
      _showError(e.toString());
    }
  }

  Future<void> _toggleMute() async {
    try {
      if (_isMuted) {
        await _callClient.unmuteAudio();
        setState(() => _isMuted = false);
        _showSuccess('Unmuted');
      } else {
        await _callClient.muteAudio();
        setState(() => _isMuted = true);
        _showSuccess('Muted');
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _toggleVideo() async {
    try {
      if (_isVideoOn) {
        await _callClient.stopVideo();
        setState(() => _isVideoOn = false);
        _showSuccess('Video stopped');
      } else {
        await _callClient.requestPermissions();
        await _callClient.startVideo();
        setState(() => _isVideoOn = true);
        _showSuccess('Video started');
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _requestPermissions() async {
    try {
      await _callClient.requestPermissions();
      _showSuccess('Permissions granted (or already granted)');
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _switchCamera() async {
    try {
      await _callClient.switchCamera();
      _showSuccess('Camera switched');
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Voice & Video Calling',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _accessTokenController,
            decoration: const InputDecoration(
              labelText: 'Access Token',
              hintText: 'Enter your access token',
              border: OutlineInputBorder(),
              helperText: 'Get this from your backend',
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _initializeCalling,
            icon: const Icon(Icons.login),
            label: const Text('Initialize Calling Client'),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _requestPermissions,
            icon: const Icon(Icons.verified_user),
            label: const Text('Request Permissions'),
          ),
          const Divider(height: 32),
          SwitchListTile(
            value: _joinWithVideo,
            onChanged: _isInCall
                ? null
                : (value) => setState(() => _joinWithVideo = value),
            title: const Text('Enable video when joining or starting a call'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _participantController,
            decoration: const InputDecoration(
              labelText: 'Participant ID',
              hintText: 'Enter participant user ID',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _groupCallIdController,
            decoration: const InputDecoration(
              labelText: 'Group Call ID',
              hintText: '00000000-0000-0000-0000-000000000000',
              border: OutlineInputBorder(),
              helperText: 'Join an existing ACS group call',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _meetingLinkController,
            decoration: const InputDecoration(
              labelText: 'Teams Meeting Link',
              hintText: 'https://teams.microsoft.com/l/meetup-join/...',
              border: OutlineInputBorder(),
              helperText: 'Paste the full Teams meeting URL',
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          if (!_isInCall) ...[
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _startCall,
              icon: const Icon(Icons.call),
              label: const Text('Start Call'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _joinGroupCall,
              icon: const Icon(Icons.groups),
              label: const Text('Join Group Call'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _joinTeamsMeeting,
              icon: const Icon(Icons.meeting_room),
              label: const Text('Join Teams Meeting'),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _toggleMute,
                    icon: Icon(_isMuted ? Icons.mic_off : Icons.mic),
                    label: Text(_isMuted ? 'Unmute' : 'Mute'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _toggleVideo,
                    icon: Icon(
                      _isVideoOn ? Icons.videocam : Icons.videocam_off,
                    ),
                    label: Text(_isVideoOn ? 'Stop Video' : 'Start Video'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isVideoOn ? _switchCamera : null,
              icon: const Icon(Icons.cameraswitch),
              label: const Text('Switch Camera'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _endCall,
              icon: const Icon(Icons.call_end),
              label: const Text('End Call'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Status',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(_status),
                  if (_isInCall) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.circle, size: 12, color: Colors.green),
                        const SizedBox(width: 8),
                        const Text('In call'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Local Preview',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(child: AcsLocalVideoView()),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Remote Video',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 240,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(child: AcsRemoteVideoView()),
            ),
          ),
        ],
      ),
    );
  }
}

// Chat Tab - Removed in v0.2.3 for size optimization
class ChatTab extends StatelessWidget {
  final AcsFlutterSdk sdk;

  const ChatTab({super.key, required this.sdk});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 24),
            const Text(
              'Chat Removed',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              'The Chat SDK was removed in v0.2.3 for size optimization.\n\n'
              'For chat functionality, please use:\n'
              '- AcsUiLibrary ChatComposite for pre-built UI\n'
              '- Server-side chat implementation\n'
              '- Azure Communication Services Chat SDK directly',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
