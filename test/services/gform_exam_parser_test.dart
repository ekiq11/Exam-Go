import 'package:flutter_test/flutter_test.dart';
import 'package:examgo/services/gform_exam_parser.dart';

void main() {
  test('GFormExamParser parses public Google Form and extracts questions, math and images', () async {
    final result = await GFormExamParser.parseFromUrl(
      formUrl: 'https://docs.google.com/forms/d/e/1FAIpQLScnI2EmbiCxyOEc2x94al_6sQjajxPpTJg92ZXX65gw95PK0Q/viewform?usp=dialog',
    );
    expect(result.isValid, isTrue, reason: 'Expected form to be parsed successfully');
    expect(result.package, isNotNull);
    expect(result.package!.namaPaket, equals('Soal Matematika'));
    expect(result.package!.totalSoal, equals(4));

    final questions = result.package!.subtests.first.soalList;
    expect(questions.length, equals(4));
    
    // Soal 1
    expect(questions[0].pertanyaan, contains('Berikut adalah contoh'));
    expect(questions[0].opsiA, equals('Opsi 1'));
    expect(questions[0].opsiE, equals('Opsi 5'));

    // Soal 2 (dengan gambar)
    expect(questions[1].pertanyaan, contains('logika'));
    expect(questions[1].gambar, isNotEmpty);
    expect(questions[1].gambar, contains('forms-images-rt'));

    // Soal 3 (perkalian matematika)
    expect(questions[2].pertanyaan, contains('15 + 25'));
    expect(questions[2].opsiA, equals('55'));

    // Soal 4 (persamaan kuadrat)
    expect(questions[3].pertanyaan, contains('x^{2} - 9 = 0'));
    expect(questions[3].opsiA, equals('3'));
  });
}
