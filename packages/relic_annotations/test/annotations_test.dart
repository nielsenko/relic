import 'package:relic_annotations/relic_annotations.dart';
import 'package:test/test.dart';

void main() {
  group('annotations are const-constructible', () {
    test('Api', () {
      const api = Api('/users');
      expect(api.path, '/users');
    });

    test('Get', () {
      const get = Get('/list');
      expect(get.path, '/list');
      const getDefault = Get();
      expect(getDefault.path, '/');
    });

    test('Post', () {
      const post = Post('/create');
      expect(post.path, '/create');
    });

    test('Put', () {
      const put = Put('/update');
      expect(put.path, '/update');
    });

    test('Delete', () {
      const del = Delete('/remove');
      expect(del.path, '/remove');
    });

    test('Patch', () {
      const patch = Patch('/partial');
      expect(patch.path, '/partial');
    });

    test('Path', () {
      const path = Path('id');
      expect(path.name, 'id');
      const pathDefault = Path();
      expect(pathDefault.name, isNull);
    });

    test('Query', () {
      const query = Query('page');
      expect(query.name, 'page');
      const queryDefault = Query();
      expect(queryDefault.name, isNull);
    });

    test('Header', () {
      const header = Header('Authorization');
      expect(header.name, 'Authorization');
      const headerDefault = Header();
      expect(headerDefault.name, isNull);
    });

    test('JsonBody', () {
      const body = JsonBody();
      expect(body, isA<JsonBody>());
    });

    test('FormBody', () {
      const body = FormBody();
      expect(body, isA<FormBody>());
    });

    test('Req', () {
      const req = Req();
      expect(req, isA<Req>());
    });

    test('Use', () {
      const use = Use('placeholder');
      expect(use.middleware, 'placeholder');
    });

    test('Errors', () {
      const errors = Errors([String, int]);
      expect(errors.types, hasLength(2));
    });

    test('Status', () {
      const status = Status(201);
      expect(status.code, 201);
    });
  });
}
