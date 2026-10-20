import 'package:flutter/services.dart';

const usernameMessage = '账号需为6-32位，且同时包含英文字母和数字';
const passwordMessage = '密码需为8-64位，且同时包含大写字母、小写字母和数字';

final _username = RegExp(r'^(?=.*[A-Za-z])(?=.*\d)[A-Za-z0-9]{6,32}$');
final _password = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)[A-Za-z0-9]{8,64}$');

final alphanumeric = FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'));

bool validUsername(String value) => _username.hasMatch(value.trim());

bool validPassword(String value) => _password.hasMatch(value);
