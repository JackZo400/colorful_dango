/// 双语 / Bilingual
library;
enum AppLang { zh, en }
class L10n {
  static AppLang lang = AppLang.zh;
  static String get(String key) => _s[key]?[lang.index] ?? key;
  static final _s = <String, List<String>>{
    'app_name':['三彩丸子','Colorful Dango'],'add_contact':['添加联系人','Add Contact'],
    'no_contacts':['暂无联系人','No Contacts'],'tap_to_start':['点击下方按钮开始','Tap below to start'],
    'online':['在线','Online'],'offline':['离线','Offline'],'reconnect':['重新连接','Reconnect'],
    'cancel':['取消','Cancel'],'about':['关于','About'],'close':['关闭','Close'],
    'about_content':['加密聊天，安全私密\n无需注册\n\nv1.0.0-alpha','Secure & Private Chat\nNo Registration\n\nv1.0.0-alpha'],
    'fingerprint':['身份指纹','Fingerprint'],'loading':['加载中...','Loading...'],
    'signal_tab':['信令','Server'],'lan_tab':['局域网','LAN'],'manual_tab':['手动','Manual'],
    'connect_server':['连接服务器','Connect'],'connected':['已连接','Connected'],
    'disconnect':['断开','Disconnect'],'waiting_online':['等待在线设备...','Waiting for peers...'],
    'connect_btn':['连接','Connect'],'start_scan':['开启局域网扫描','Start LAN Scan'],
    'scanning':['扫描中','Scanning'],'stop':['停止','Stop'],'waiting_lan':['等待附近设备...','Waiting...'],
    'manual_title':['手动连接','Manual Connect'],'manual_desc':['通过复制粘贴交换数据','Exchange data via copy & paste'],
    'create_offer':['发起连接','Initiate'],'paste_offer':['响应连接','Respond'],
    'paste_dialog':['粘贴对方数据','Paste Data'],'data_ready':['连接数据已就绪','Data Ready'],
    'answer_ready':['应答数据已就绪','Response Ready'],'copy':['复制','Copy'],'copied':['已复制','Copied'],
    'share':['分享','Share'],'paste_answer':['粘贴对方应答','Paste Response'],
    'paste_answer_hint':['粘贴应答数据...','Paste response...'],'send':['发送','Send'],
    'input_msg':['输入消息...','Message...'],'waiting':['等待连接...','Waiting...'],
    'encrypted':['已加密 · 安全','Encrypted · Secure'],'connecting':['连接中...','Connecting...'],
    'first_msg':['发送第一条消息','Send your first message'],'clear_chat':['清空聊天','Clear Chat'],
    'clear_confirm':['删除双方的所有聊天记录？','Delete all messages?'],'clear':['清空','Clear'],
    'recall':['撤回','Recall'],'quote':['引用','Quote'],'you_recalled':['你撤回了一条消息','You recalled a message'],
    'peer_recalled':['对方撤回了一条消息','A message was recalled'],'send_failed':['发送失败','Send Failed'],
    'create_failed':['创建失败','Failed'],'connect_failed':['连接失败','Connection Failed'],
    'process_failed':['处理失败','Failed'],'new_chat':['新建聊天','New Chat'],
    'splash_subtitle':['安全私密的聊天应用','Secure & Private Chat'],
  };
}
