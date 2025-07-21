const vision = require('@google-cloud/vision');

async function testVisionAPI() {
  try {
    console.log('🔍 Google Cloud Vision API テスト開始');
    
    // Vision APIクライアントを作成
    const client = new vision.ImageAnnotatorClient();
    
    // テスト用の簡単な画像（base64エンコード済みの小さな画像）
    const testImageBase64 = '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQFxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMKChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCj/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAv/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABmX/9k=';
    
    // OCR処理を実行
    const [result] = await client.textDetection({
      image: {
        content: testImageBase64
      }
    });
    
    console.log('✅ Google Cloud Vision API テスト成功');
    console.log('検出されたテキスト:', result.textAnnotations);
    
  } catch (error) {
    console.error('❌ Google Cloud Vision API テストエラー:', error.message);
    
    if (error.code === 7) {
      console.log('💡 解決方法:');
      console.log('1. Google Cloud Consoleで Vision API を有効化してください');
      console.log('2. 5-10分待機してから再度テストしてください');
      console.log('3. プロジェクトがBlaze（従量課金）プランになっていることを確認してください');
    }
  }
}

testVisionAPI(); 