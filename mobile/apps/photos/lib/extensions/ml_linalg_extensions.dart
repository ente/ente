import 'dart:math' as math show sin, cos, atan2, sqrt, pow;
import 'package:ml_linalg/linalg.dart';

extension SetVectorValues on Vector {
  Vector setValues(int start, int end, Iterable<double> values) {
    if (values.length > length) {
      throw Exception('Values cannot be larger than vector');
    } else if (end - start != values.length) {
      throw Exception('Values must be same length as range');
    } else if (start < 0 || end > length) {
      throw Exception('Range must be within vector');
    }
    final tempList = toList();
    tempList.replaceRange(start, end, values);
    final newVector = Vector.fromList(tempList);
    return newVector;
  }
}

extension SetMatrixValues on Matrix {
  Matrix setSubMatrix(
    int startRow,
    int endRow,
    int startColumn,
    int endColumn,
    Iterable<Iterable<double>> values,
  ) {
    if (values.length > rowCount) {
      throw Exception('New values cannot have more rows than original matrix');
    } else if (values.elementAt(0).length > columnCount) {
      throw Exception(
        'New values cannot have more columns than original matrix',
      );
    } else if (endRow - startRow != values.length) {
      throw Exception('Values (number of rows) must be same length as range');
    } else if (endColumn - startColumn != values.elementAt(0).length) {
      throw Exception(
        'Values (number of columns) must be same length as range',
      );
    } else if (startRow < 0 ||
        endRow > rowCount ||
        startColumn < 0 ||
        endColumn > columnCount) {
      throw Exception('Range must be within matrix');
    }
    final tempList = asFlattenedList
        .toList(); // You need `.toList()` here to make sure the list is growable, otherwise `replaceRange` will throw an error
    for (var i = startRow; i < endRow; i++) {
      tempList.replaceRange(
        i * columnCount + startColumn,
        i * columnCount + endColumn,
        values.elementAt(i).toList(),
      );
    }
    final newMatrix = Matrix.fromFlattenedList(tempList, rowCount, columnCount);
    return newMatrix;
  }

  Matrix setValues(
    int startRow,
    int endRow,
    int startColumn,
    int endColumn,
    Iterable<double> values,
  ) {
    if ((startRow - endRow) * (startColumn - endColumn) != values.length) {
      throw Exception('Values must be same length as range');
    } else if (startRow < 0 ||
        endRow > rowCount ||
        startColumn < 0 ||
        endColumn > columnCount) {
      throw Exception('Range must be within matrix');
    }

    final tempList = asFlattenedList
        .toList(); // You need `.toList()` here to make sure the list is growable, otherwise `replaceRange` will throw an error
    var index = 0;
    for (var i = startRow; i < endRow; i++) {
      for (var j = startColumn; j < endColumn; j++) {
        tempList[i * columnCount + j] = values.elementAt(index);
        index++;
      }
    }
    final newMatrix = Matrix.fromFlattenedList(tempList, rowCount, columnCount);
    return newMatrix;
  }

  Matrix setValue(int row, int column, double value) {
    if (row < 0 || row > rowCount || column < 0 || column > columnCount) {
      throw Exception('Index must be within range of matrix');
    }
    final tempList = asFlattenedList;
    tempList[row * columnCount + column] = value;
    final newMatrix = Matrix.fromFlattenedList(tempList, rowCount, columnCount);
    return newMatrix;
  }

  Matrix appendRow(List<double> row) {
    final oldNumberOfRows = rowCount;
    final oldNumberOfColumns = columnCount;
    if (row.length != oldNumberOfColumns) {
      throw Exception('Row must have same number of columns as matrix');
    }
    final flatListMatrix = asFlattenedList;
    flatListMatrix.addAll(row);
    return Matrix.fromFlattenedList(
      flatListMatrix,
      oldNumberOfRows + 1,
      oldNumberOfColumns,
    );
  }
}

extension MatrixCalculations on Matrix {
  double determinant() {
    final int length = rowCount;
    if (length != columnCount) {
      throw Exception('Matrix must be square');
    }
    if (length == 1) {
      return this[0][0];
    } else if (length == 2) {
      return this[0][0] * this[1][1] - this[0][1] * this[1][0];
    } else {
      throw Exception('Determinant for Matrix larger than 2x2 not implemented');
    }
  }

  /// Computes the singular value decomposition of a matrix, using https://lucidar.me/en/mathematics/singular-value-decomposition-of-a-2x2-matrix/ as reference, but with slightly different signs for the second columns of U and V
  Map<String, dynamic> svd() {
    if (rowCount != 2 || columnCount != 2) {
      throw Exception('Matrix must be 2x2');
    }
    final a = this[0][0];
    final b = this[0][1];
    final c = this[1][0];
    final d = this[1][1];

    // Computation of U matrix
    final tempCalc = a * a + b * b - c * c - d * d;
    final theta = 0.5 * math.atan2(2 * a * c + 2 * b * d, tempCalc);
    final U = Matrix.fromList([
      [math.cos(theta), math.sin(theta)],
      [math.sin(theta), -math.cos(theta)],
    ]);

    // Computation of S matrix
    // ignore: non_constant_identifier_names
    final S1 = a * a + b * b + c * c + d * d;
    // ignore: non_constant_identifier_names
    final S2 = math.sqrt(
      math.pow(tempCalc, 2) + 4 * math.pow(a * c + b * d, 2),
    );
    final sigma1 = math.sqrt((S1 + S2) / 2);
    final sigma2 = math.sqrt((S1 - S2) / 2);
    final S = Vector.fromList([sigma1, sigma2]);

    // Computation of V matrix
    final tempCalc2 = a * a - b * b + c * c - d * d;
    final phi = 0.5 * math.atan2(2 * a * b + 2 * c * d, tempCalc2);
    final s11 =
        (a * math.cos(theta) + c * math.sin(theta)) * math.cos(phi) +
        (b * math.cos(theta) + d * math.sin(theta)) * math.sin(phi);
    final s22 =
        (a * math.sin(theta) - c * math.cos(theta)) * math.sin(phi) +
        (-b * math.sin(theta) + d * math.cos(theta)) * math.cos(phi);
    final V = Matrix.fromList([
      [s11.sign * math.cos(phi), s22.sign * math.sin(phi)],
      [s11.sign * math.sin(phi), -s22.sign * math.cos(phi)],
    ]);

    return {'U': U, 'S': S, 'V': V};
  }

  int matrixRank() {
    final svdResult = svd();
    final Vector S = svdResult['S']!;
    final rank = S.toList().where((element) => element > 1e-10).length;
    return rank;
  }
}

extension TransformMatrix on Matrix {
  List<List<double>> to2DList() {
    final List<List<double>> outerList = [];
    for (var i = 0; i < rowCount; i++) {
      final innerList = this[i].toList();
      outerList.add(innerList);
    }
    return outerList;
  }
}
