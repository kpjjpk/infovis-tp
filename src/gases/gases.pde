String DATA_DIR = "../../data/processed";
String GASES_DIR = dataDir("gas");
String IMG_DIR = dataDir("images");
String FACTORIES_FILE = _dataFile("factories");
String MONITORS_FILE = _dataFile("monitors");
String WINDS_FILE = _dataFile("winds");

int areaDim = 200;
float gasScaleFactor = 200;
float windScaleFactor = 20;
String chemical = "methylosmolene";

float offsetX = -50;
float offsetY = +20;

float scaleFactorX = 5;
float scaleFactorY = 5;

float timeX;
float timeY;
float weathervaneX;
float weathervaneY;

float[][] winds;
String[] times;

int n = -1;

void setup() {
  size(600, 500);
  frameRate(4000);
  surface.setResizable(true);

  winds = loadFloatsFromCSV(WINDS_FILE, 1, 2);
  times = loadLabelsFromCSV(WINDS_FILE, 0);
}

void draw() {
  n += 1;

  if (areAllSaved()) {
    noLoop();
  }

  try {
    background(#FFFFFF);
    fixCoords();

    recalculateScale();

    drawText(times[n], timeX, timeY);

    drawFactories(FACTORIES_FILE, 0, 1, 2, #000000, 5);
    drawMonitors(MONITORS_FILE, 0, 1, 2, #0000FF, 5);
    drawGasPoints(gasesFile(chemical, n), 0, 2, #8B4513, 2);

    drawText("N", weathervaneX + 2, weathervaneY + 20);
    drawArrow(weathervaneX, weathervaneY, 20, 0, #000000, 2);

    if (n > 0) {
      drawWeathervane(n - 1, weathervaneX, weathervaneY, #808080, 2);
    }
    drawWeathervane(n, weathervaneX, weathervaneY, #000000, 2);

    if (!areAllSaved()) {
      save(outputImage(chemical, n));
    }
  } catch (Exception e) {
    // last file reached
    noLoop();
  }
}

void drawGasPoints(String path, int fromCol, int toCol, int rgb, int _width) {
  float[][] points = loadFloatsFromCSV(path, fromCol, toCol);

  for (float[] row : points) {
    float x = row[0];
    float y = row[1];
    float reading = row[2];

    stroke(rgb, reading * gasScaleFactor);
    drawPoint(x, y, _width);
  }
}

void drawFactories(String path, int labelCol, int xCol, int yCol, int rgb, int _width) {
  String[] names = loadLabelsFromCSV(path, labelCol);
  float[][] positions = loadFloatsFromCSV(path, xCol, yCol);

  for (int i = 0; i < positions.length; i++) {
    float x = positions[i][0];
    float y = positions[i][1];

    String label = "";
    for (String word : names[i].split(" ")) { 
      label += word.toUpperCase().charAt(0);
    }

    drawPointWithLabel(x, y, label, rgb, _width);
  }
}

void drawMonitors(String path, int labelCol, int xCol, int yCol, int rgb, int _width) {
  String[] labels = loadLabelsFromCSV(path, labelCol);
  float[][] positions = loadFloatsFromCSV(path, xCol, yCol);

  for (int i = 0; i < positions.length; i++) {
    float x = positions[i][0];
    float y = positions[i][1];

    drawPointWithLabel(x, y, "M" + labels[i], rgb, _width);
  }
}

void drawPoints(String path, int fromCol, int toCol, int rgb, int _width) {
  float[][] points = loadFloatsFromCSV(path, fromCol, toCol);

  stroke(rgb);

  for (float[] row : points) {
    float x = row[0];
    float y = row[1];
    
    drawPoint(x, y, _width);
  }
}

void drawPoint(float x, float y, float _width) {
  float shiftedX = x + offsetX;
  float shiftedY = y + offsetY;
  
  strokeWeight(_width);
  point(shiftedX * scaleFactorX, shiftedY * scaleFactorY);
}

void drawPointWithLabel(float x, float y, String label, int rgb, float _width) {
  float shiftedX = x + offsetX;
  float shiftedY = y + offsetY;
  
  stroke(#000000);
  drawText(label, (shiftedX + 1) * scaleFactorX, (shiftedY + 1) * scaleFactorY);

  stroke(rgb);
  drawPoint(x, y, _width);
}

void drawWeathervane(int n, float x, float y, int rgb, int _width) {
  float[] wind = winds[n];
  float phi = radians(wind[0]);
  float speed = wind[1];
  drawArrow(x, y, speed * windScaleFactor, phi, rgb, _width);
}

void drawArrow(float x1, float y1, float r, float phi, int rgb, int _width) {
  stroke(rgb);
  fill(rgb);
  strokeWeight(_width);

  float x2 = x1 + r * sin(phi);
  float y2 = y1 + r * cos(phi);
  float a = dist(x1, y1, x2, y2) / 20;
  pushMatrix();
  translate(x2, y2);
  rotate(atan2(y2 - y1, x2 - x1));
  triangle(- a * 2 , - a, 0, 0, - a * 2, a);
  popMatrix();
  line(x1, y1, x2, y2);
}

void drawText(String txt, float x, float y) {
  pushMatrix();
  translate(x, y);
  scale(1, -1);
  text(txt, 0, 0);
  popMatrix();
}

float[][] loadFloatsFromCSV(String path, int fromCol, int toCol) {
  String[] lines = loadStrings(path);
  float[][] values = new float[lines.length - 1][toCol - fromCol + 1];

  for (int i = 1; i < lines.length; i++) {
    String[] lineValues = split(lines[i], ',');

    for (int j = fromCol; j < toCol + 1; j++) {
      values[i - 1][j - fromCol] = float(lineValues[j]);
    }
  }
  return values;
}

String[] loadLabelsFromCSV(String path, int col) {
  String[] lines = loadStrings(path);
  String[] values = new String[lines.length - 1];

  for (int i = 1; i < lines.length; i++) {
    String[] lineValues = split(lines[i], ',');
    values[i - 1] = lineValues[col];
  }
  return values;
}

String gasesFile(String chemical, int n) {
  return GASES_DIR + "/" + chemical + "/" + n + ".csv";
}

String outputImage(String chemical, int n) {
  return IMG_DIR + "/" + chemical + "/" + times[n].replace('/', '-') + ".png";
}

String dataDir(String path) {
  return DATA_DIR + "/" + path;
}

String _dataFile(String path) {
  return DATA_DIR + "/" + path + ".csv";
}

void recalculateScale() {
  //scaleFactorX = width / areaDim;
  //scaleFactorY = height / areaDim;
  timeX = width * 0.1;
  timeY = height * 0.9;
  weathervaneX = width * 0.9;
  weathervaneY = height * 0.9;
}

void fixCoords() {
  scale(1, -1);
  translate(0, -height);
}

boolean areAllSaved() {
  return n >= times.length;
}