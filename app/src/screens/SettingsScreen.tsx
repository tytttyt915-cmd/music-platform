/**
* 我的页：昵称 / 游客-登录状态展示、登录切换、退出登录、
* （二次确认 → 服务端删除 → 清本地登录态 → 重建游客身份，
* Apple Guideline 5.1.1(v) 合规闭环）。
*/
import React, {useCallback, useEffect, useState} from 'react';
import {
ActivityIndicator,
Alert,
Pressable,
StyleSheet,
Text,
View,
} from 'react-native';
import {
ApiError,
LocalProfile,
deleteAccount,
getLocalProfile,
guestLogin,
logout,
} from '../api/client';
import AuthScreen from './AuthScreen';

export default function SettingsScreen() {
const [profile, setProfile] = useState<LocalProfile>({
nickname: '游客',
isGuest: true,
});
const [authVisible, setAuthVisible] = useState(false);
const [busy, setBusy] = useState(false);

const reload = useCallback(async () => {
try {
setProfile(await getLocalProfile());
} catch (e) {
console.warn('[Settings] 读取本地账号状态失败', e);
}
}, []);

useEffect(() => {
reload();
}, [reload]);

/** 退出登录 → 回到纯净游客试听身份 */
const onLogout = () => {
Alert.alert('退出登录', '退出后将以游客身份继续试听', [
{text: '取消', style: 'cancel'},
{
text: '退出登录',
onPress: async () => {
setBusy(true);
try {
await logout();
await guestLogin();
await reload();
} catch (e) {
Alert.alert(
'失败',
e instanceof ApiError? e.message: '退出登录失败，请重试',
);
} finally {
setBusy(false);
}
},
},
]);
};

/**
* 注销账号（Apple 5.1.1(v)）：
* 二次确认 → DELETE /account（服务端永久删除账号及云端数据）
* → 本地清登录态 → 自动重建游客身份，保证 App 可继续试听。
*/
const onDeleteAccount = () => {
Alert.alert(
'注销账号',
'将永久删除该账号及云端数据，此操作不可恢复。注销后将自动切换为游客身份。',
[
{text: '取消', style: 'cancel'},
{
text: '确认注销',
style: 'destructive',
onPress: async () => {
setBusy(true);
try {
await deleteAccount();
await guestLogin();
await reload();
Alert.alert('已注销', '账号已永久删除，现为游客身份');
} catch (e) {
Alert.alert(
'注销失败',
e instanceof ApiError? e.message: '注销失败，请稍后重试',
);
} finally {
setBusy(false);
}
},
},
],
);
};

return (
<View style={styles.container}>
<Text style={styles.header}>我的</Text>

{/* 账号卡片 */}
<View style={styles.card}>
<View style={styles.avatar}>
<Text style={styles.avatarText}>
{profile.nickname.slice(0, 1).toUpperCase()}
</Text>
</View>
<View style={styles.cardMeta}>
<Text style={styles.nickname}>{profile.nickname}</Text>
<View
style={[
styles.badge,
profile.isGuest? styles.badgeGuest: styles.badgeUser,
]}>
<Text style={styles.badgeText}>
{profile.isGuest? '游客试听中': '已登录'}
</Text>
</View>
</View>
</View>

{/* 操作区 */}
<Pressable style={styles.row} onPress={() => setAuthVisible(true)}>
<Text style={styles.rowText}>
{profile.isGuest? '登录 / 绑定账号': '切换账号'}
</Text>
<Text style={styles.rowArrow}>›</Text>
</Pressable>

{!profile.isGuest && (
<Pressable style={styles.row} onPress={onLogout} disabled={busy}>
<Text style={styles.rowText}>退出登录</Text>
<Text style={styles.rowArrow}>›</Text>
</Pressable>
)}

<View style={styles.dangerZone}>
<Text style={styles.dangerTitle}>账号安全</Text>
<Pressable
style={[styles.deleteBtn, busy && styles.btnDisabled]}
disabled={busy}
onPress={onDeleteAccount}>
{busy? (
<ActivityIndicator size="small" color="#ff5c7a" />
): (
<Text style={styles.deleteText}>注销账号</Text>
)}
</Pressable>
<Text style={styles.dangerHint}>
注销将永久删除账号及云端数据，且不可恢复
</Text>
</View>

<AuthScreen
visible={authVisible}
onClose={() => setAuthVisible(false)}
onSuccess={reload}
/>
</View>
);
}

const styles = StyleSheet.create({
container: {
flex: 1,
backgroundColor: '#0a0a0f',
paddingTop: 56,
paddingHorizontal: 16,
},
header: {
color: '#fff',
fontSize: 24,
fontWeight: '800',
marginBottom: 16,
},
card: {
flexDirection: 'row',
alignItems: 'center',
backgroundColor: 'rgba(255,255,255,0.06)',
borderRadius: 14,
padding: 16,
marginBottom: 16,
},
avatar: {
width: 56,
height: 56,
borderRadius: 28,
backgroundColor: '#ff5c7a',
justifyContent: 'center',
alignItems: 'center',
},
avatarText: {
color: '#fff',
fontSize: 24,
fontWeight: '700',
},
cardMeta: {
marginLeft: 14,
flex: 1,
},
nickname: {
color: '#fff',
fontSize: 18,
fontWeight: '700',
},
badge: {
alignSelf: 'flex-start',
borderRadius: 10,
paddingHorizontal: 8,
paddingVertical: 3,
marginTop: 6,
},
badgeGuest: {
backgroundColor: 'rgba(255,255,255,0.12)',
},
badgeUser: {
backgroundColor: 'rgba(7,193,96,0.2)',
},
badgeText: {
color: '#fff',
fontSize: 11,
},
row: {
flexDirection: 'row',
justifyContent: 'space-between',
alignItems: 'center',
backgroundColor: 'rgba(255,255,255,0.06)',
borderRadius: 12,
paddingHorizontal: 16,
paddingVertical: 14,
marginBottom: 10,
},
rowText: {
color: '#fff',
fontSize: 15,
},
rowArrow: {
color: 'rgba(255,255,255,0.4)',
fontSize: 18,
},
dangerZone: {
marginTop: 24,
borderTopWidth: StyleSheet.hairlineWidth,
borderTopColor: 'rgba(255,255,255,0.1)',
paddingTop: 16,
},
dangerTitle: {
color: 'rgba(255,255,255,0.5)',
fontSize: 13,
marginBottom: 10,
},
deleteBtn: {
borderWidth: 1,
borderColor: 'rgba(255,92,122,0.5)',
borderRadius: 12,
paddingVertical: 13,
alignItems: 'center',
},
btnDisabled: {
opacity: 0.6,
},
deleteText: {
color: '#ff5c7a',
fontSize: 15,
fontWeight: '600',
},
dangerHint: {
color: 'rgba(255,255,255,0.35)',
fontSize: 12,
textAlign: 'center',
marginTop: 8,
},
});
