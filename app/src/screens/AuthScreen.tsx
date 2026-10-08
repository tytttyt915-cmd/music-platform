/**
 * 登录页（Modal）：微信登录 + 手机号验证码登录。
 *
 * 注意：微信原生 SDK 尚未接入客户端，此处微信登录走后端 Mock 联调通道
 *（AUTH_MOCK=true 时任意 code 可登录）；正式上线前需接入微信 SDK
 *（如 react-native-wechat-lib）并配置真实 AppID 后再替换此处实现。
 * 手机号登录为两步：sendSms 发送验证码 → verifySms 校验并登录。
 */
import React, {useState} from 'react';
import {
  ActivityIndicator,
  Alert,
  Modal,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import {
  ApiError,
  guestLogin,
  sendSms,
  verifySms,
  wechatLogin,
} from '../api/client';

interface Props {
  visible: boolean;
  onClose: () => void;
  /** 登录成功后回调（调用方刷新账号状态） */
  onSuccess: () => void;
}

/** 手机号格式校验：1 开头 11 位 */
function isValidPhone(phone: string): boolean {
  return /^1\d{10}$/.test(phone.trim());
}

export default function AuthScreen({visible, onClose, onSuccess}: Props) {
  const [phone, setPhone] = useState('');
  const [code, setCode] = useState('');
  const [sending, setSending] = useState(false);
  const [verifying, setVerifying] = useState(false);
  const [wechatBusy, setWechatBusy] = useState(false);

  const finish = () => {
    onSuccess();
    onClose();
  };

  /** 微信登录：无真实 AppID 时明确提示，走后端 Mock 通道联调 */
  const onWechatLogin = () => {
    Alert.alert(
      '微信登录',
      '客户端尚未接入微信原生 SDK，将使用后端 Mock 通道以测试账号登录。正式上线前请配置真实微信 AppID 并接入 SDK。',
      [
        {text: '取消', style: 'cancel'},
        {
          text: '继续登录',
          onPress: async () => {
            setWechatBusy(true);
            try {
              // Mock 通道：code 仅用于区分测试用户
              await wechatLogin(`mock:${Date.now()}`);
              finish();
            } catch (e) {
              Alert.alert(
                '登录失败',
                e instanceof ApiError ? e.message : '微信登录失败，请稍后重试',
              );
            } finally {
              setWechatBusy(false);
            }
          },
        },
      ],
    );
  };

  const onSendSms = async () => {
    if (!isValidPhone(phone)) {
      Alert.alert('提示', '请输入正确的 11 位手机号');
      return;
    }
    setSending(true);
    try {
      const res = await sendSms(phone.trim());
      Alert.alert(
        '验证码已发送',
        res.mock
          ? '当前为短信 Mock 模式，验证码请查看后端日志（默认 123456）'
          : '请查看手机短信并输入验证码',
      );
    } catch (e) {
      Alert.alert(
        '发送失败',
        e instanceof ApiError ? e.message : '验证码发送失败，请稍后重试',
      );
    } finally {
      setSending(false);
    }
  };

  const onVerifySms = async () => {
    if (!isValidPhone(phone)) {
      Alert.alert('提示', '请输入正确的 11 位手机号');
      return;
    }
    if (!code.trim()) {
      Alert.alert('提示', '请输入短信验证码');
      return;
    }
    setVerifying(true);
    try {
      await verifySms(phone.trim(), code.trim());
      finish();
    } catch (e) {
      Alert.alert(
        '登录失败',
        e instanceof ApiError ? e.message : '验证码校验失败，请重试',
      );
    } finally {
      setVerifying(false);
    }
  };

  /** 游客身份回退：已登录用户可一键回到纯净游客试听 */
  const onBackToGuest = async () => {
    try {
      await guestLogin();
      finish();
    } catch (e) {
      Alert.alert(
        '失败',
        e instanceof ApiError ? e.message : '切换游客身份失败，请检查网络',
      );
    }
  };

  return (
    <Modal
      visible={visible}
      animationType="slide"
      onRequestClose={onClose}
      statusBarTranslucent>
      <View style={styles.container}>
        <View style={styles.header}>
          <Pressable onPress={onClose} hitSlop={16} style={styles.closeBtn}>
            <Text style={styles.closeText}>✕</Text>
          </Pressable>
          <Text style={styles.headerTitle}>登录 / 注册</Text>
          <Text style={styles.versionText}>v1.0.6</Text>
        </View>

        {/* 微信登录 */}
        <Pressable
          style={[styles.wechatBtn, wechatBusy && styles.btnDisabled]}
          disabled={wechatBusy}
          onPress={onWechatLogin}>
          {wechatBusy ? (
            <ActivityIndicator size="small" color="#fff" />
          ) : (
            <Text style={styles.wechatText}>微信一键登录</Text>
          )}
        </Pressable>
        <Text style={styles.hint}>未接入微信 SDK 时走后端 Mock 通道联调</Text>

        <View style={styles.divider}>
          <View style={styles.dividerLine} />
          <Text style={styles.dividerText}>或手机号登录</Text>
          <View style={styles.dividerLine} />
        </View>

        {/* 手机号验证码登录 */}
        <View style={styles.phoneRow}>
          <TextInput
            style={[styles.input, styles.phoneInput]}
            placeholder="手机号"
            placeholderTextColor="rgba(255,255,255,0.35)"
            keyboardType="phone-pad"
            maxLength={11}
            value={phone}
            onChangeText={setPhone}
          />
          <Pressable
            style={[styles.sendBtn, sending && styles.btnDisabled]}
            disabled={sending}
            onPress={onSendSms}>
            {sending ? (
              <ActivityIndicator size="small" color="#fff" />
            ) : (
              <Text style={styles.sendText}>获取验证码</Text>
            )}
          </Pressable>
        </View>
        <TextInput
          style={styles.input}
          placeholder="短信验证码"
          placeholderTextColor="rgba(255,255,255,0.35)"
          keyboardType="number-pad"
          maxLength={6}
          value={code}
          onChangeText={setCode}
        />
        <Pressable
          style={[styles.loginBtn, verifying && styles.btnDisabled]}
          disabled={verifying}
          onPress={onVerifySms}>
          {verifying ? (
            <ActivityIndicator size="small" color="#fff" />
          ) : (
            <Text style={styles.loginText}>登录</Text>
          )}
        </Pressable>

        <Pressable style={styles.guestLink} onPress={onBackToGuest}>
          <Text style={styles.guestText}>继续以游客身份试听 →</Text>
        </Pressable>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0a0a0f',
    paddingTop: 56,
    paddingHorizontal: 24,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 32,
  },
  closeBtn: {
    width: 40,
    height: 40,
    justifyContent: 'center',
    alignItems: 'center',
  },
  closeText: {
    color: '#fff',
    fontSize: 18,
  },
  headerTitle: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '700',
  },
  versionText: {
    color: '#666',
    fontSize: 11,
    position: 'absolute',
    right: 16,
  },
  wechatBtn: {
    backgroundColor: '#07c160',
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: 'center',
  },
  wechatText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  btnDisabled: {
    opacity: 0.6,
  },
  hint: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 12,
    textAlign: 'center',
    marginTop: 8,
  },
  divider: {
    flexDirection: 'row',
    alignItems: 'center',
    marginVertical: 28,
  },
  dividerLine: {
    flex: 1,
    height: StyleSheet.hairlineWidth,
    backgroundColor: 'rgba(255,255,255,0.15)',
  },
  dividerText: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 13,
    marginHorizontal: 12,
  },
  phoneRow: {
    flexDirection: 'row',
    marginBottom: 12,
  },
  input: {
    backgroundColor: 'rgba(255,255,255,0.08)',
    borderRadius: 10,
    paddingHorizontal: 14,
    paddingVertical: 12,
    color: '#fff',
    fontSize: 15,
    marginBottom: 12,
  },
  phoneInput: {
    flex: 1,
    marginBottom: 0,
  },
  sendBtn: {
    marginLeft: 10,
    backgroundColor: 'rgba(255,255,255,0.12)',
    borderRadius: 10,
    paddingHorizontal: 14,
    justifyContent: 'center',
  },
  sendText: {
    color: '#fff',
    fontSize: 14,
  },
  loginBtn: {
    backgroundColor: '#ff5c7a',
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: 'center',
    marginTop: 4,
  },
  loginText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  guestLink: {
    marginTop: 28,
    alignItems: 'center',
  },
  guestText: {
    color: 'rgba(255,255,255,0.55)',
    fontSize: 14,
  },
});
