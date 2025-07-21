import {Storage} from "@google-cloud/storage";
import * as vision from "@google-cloud/vision";

/**
 * OCR認証サービス
 * Google Cloud Vision APIを使用して身分証明書から情報を抽出
 */
export class OCRService {
  private visionClient: vision.ImageAnnotatorClient;
  private storage: Storage;

  /**
   * OCRServiceのコンストラクタ
   */
  constructor() {
    this.visionClient = new vision.ImageAnnotatorClient();
    this.storage = new Storage();
  }

  /**
   * 身分証明書から情報を抽出
   * @param {string} imageUrl - 画像のURL
   * @param {string} documentType - 身分証明書の種類
   * @return {Promise<object>} 抽出結果
   */
  async extractIdentityInfo(
    imageUrl: string,
    documentType: string
  ): Promise<{
    extractedName?: string;
    extractedBirthDate?: string;
    extractedAge?: number;
    confidence: number;
    needsManualReview: boolean;
    ocrText: string;
  }> {
    try {
      console.log(`🔍 OCR処理開始: ${imageUrl}`);

      // Cloud Storageから画像を取得
      const bucketName = imageUrl.split("/")[2]; // gs://bucket-name/path から bucket-name を抽出
      const filePath = imageUrl.replace(`gs://${bucketName}/`, "");
      const [imageBuffer] = await this.storage
        .bucket(bucketName)
        .file(filePath)
        .download();

      // Vision APIでテキスト抽出
      const [result] = await this.visionClient.textDetection({
        image: {content: imageBuffer},
      });

      const detections = result.textAnnotations;
      if (!detections || detections.length === 0) {
        throw new Error("テキストが検出されませんでした");
      }

      const ocrText = detections[0].description || "";
      console.log(`📝 抽出されたテキスト: ${ocrText}`);

      // 身分証明書の種類に応じて情報を抽出
      const extractedInfo = this.parseDocumentText(ocrText, documentType);

      // 信頼度を計算
      const confidence = this.calculateConfidence(extractedInfo, ocrText);

      // 人的確認が必要かどうかを判定
      const needsManualReview = confidence < 0.8 ||
                               !extractedInfo.extractedName ||
                               !extractedInfo.extractedBirthDate;

      return {
        ...extractedInfo,
        confidence,
        needsManualReview,
        ocrText,
      };
    } catch (error) {
      console.error("❌ OCR処理エラー:", error);
      return {
        confidence: 0,
        needsManualReview: true,
        ocrText: "",
      };
    }
  }

  /**
   * 身分証明書の種類に応じてテキストを解析
   * @param {string} text - OCRで抽出されたテキスト
   * @param {string} documentType - 身分証明書の種類
   * @return {object} 抽出された情報
   */
  private parseDocumentText(
    text: string,
    documentType: string
  ): {
    extractedName?: string;
    extractedBirthDate?: string;
    extractedAge?: number;
  } {
    const result: {
      extractedName?: string;
      extractedBirthDate?: string;
      extractedAge?: number;
    } = {};

    switch (documentType) {
    case "drivers_license":
      result.extractedName = this.extractNameFromDriversLicense(text);
      result.extractedBirthDate =
          this.extractBirthDateFromDriversLicense(text);
      break;
    case "passport":
      result.extractedName = this.extractNameFromPassport(text);
      result.extractedBirthDate = this.extractBirthDateFromPassport(text);
      break;
    case "mynumber_card":
      result.extractedName = this.extractNameFromMyNumberCard(text);
      result.extractedBirthDate =
          this.extractBirthDateFromMyNumberCard(text);
      break;
    case "residence_card":
      result.extractedName = this.extractNameFromResidenceCard(text);
      result.extractedBirthDate =
          this.extractBirthDateFromResidenceCard(text);
      break;
    }

    // 年齢を計算
    if (result.extractedBirthDate) {
      result.extractedAge = this.calculateAge(result.extractedBirthDate);
    }

    return result;
  }

  /**
   * 運転免許証から氏名を抽出
   * @param {string} text - OCRテキスト
   * @return {string|undefined} 抽出された氏名
   */
  private extractNameFromDriversLicense(text: string): string | undefined {
    // 運転免許証の氏名パターンを検索
    const namePatterns = [
      /氏名\s*([^\n\r]+)/,
      /名前\s*([^\n\r]+)/,
      /([一-龯ひ-ゖァ-ヶー]+\s+[一-龯ひ-ゖァ-ヶー]+)/,
    ];

    for (const pattern of namePatterns) {
      const match = text.match(pattern);
      if (match && match[1]) {
        return match[1].trim();
      }
    }

    return undefined;
  }

  /**
   * 運転免許証から生年月日を抽出
   * @param {string} text - OCRテキスト
   * @return {string|undefined} 抽出された生年月日
   */
  private extractBirthDateFromDriversLicense(
    text: string
  ): string | undefined {
    // 生年月日のパターンを検索
    const datePatterns = [
      /生年月日\s*([0-9]{4})[年/\-.]([0-9]{1,2})[月/\-.]([0-9]{1,2})/,
      /([0-9]{4})[年/\-.]([0-9]{1,2})[月/\-.]([0-9]{1,2})/,
      /([平成|昭和|令和])([0-9]{1,2})年([0-9]{1,2})月([0-9]{1,2})日/,
    ];

    for (const pattern of datePatterns) {
      const match = text.match(pattern);
      if (match) {
        if (match[1] && match[2] && match[3] && !isNaN(Number(match[1]))) {
          // 西暦形式
          const year = match[1];
          const month = match[2].padStart(2, "0");
          const day = match[3].padStart(2, "0");
          return `${year}-${month}-${day}`;
        } else if (match[1] && match[2] && match[3] && match[4]) {
          // 和暦形式
          const era = match[1];
          const eraYear = parseInt(match[2]);
          const month = match[3].padStart(2, "0");
          const day = match[4].padStart(2, "0");

          const westernYear = this.convertEraToWestern(era, eraYear);
          if (westernYear) {
            return `${westernYear}-${month}-${day}`;
          }
        }
      }
    }

    return undefined;
  }

  /**
   * パスポートから氏名を抽出
   * @param {string} text - OCRテキスト
   * @return {string|undefined} 抽出された氏名
   */
  private extractNameFromPassport(text: string): string | undefined {
    // パスポートの氏名パターン（英語・日本語両対応）
    const namePatterns = [
      /Given Names?\s*([A-Z\s]+)/i,
      /Surname\s*([A-Z\s]+)/i,
      /氏名\s*([^\n\r]+)/,
    ];

    for (const pattern of namePatterns) {
      const match = text.match(pattern);
      if (match && match[1]) {
        return match[1].trim();
      }
    }

    return undefined;
  }

  /**
   * パスポートから生年月日を抽出
   * @param {string} text - OCRテキスト
   * @return {string|undefined} 抽出された生年月日
   */
  private extractBirthDateFromPassport(text: string): string | undefined {
    // パスポートの生年月日パターン
    const datePatterns = [
      /Date of Birth\s*([0-9]{2})\s*([A-Z]{3})\s*([0-9]{4})/i,
      /生年月日\s*([0-9]{4})[年/\-.]([0-9]{1,2})[月/\-.]([0-9]{1,2})/,
    ];

    for (const pattern of datePatterns) {
      const match = text.match(pattern);
      if (match) {
        if (match[1] && match[2] && match[3] && match[2].length === 3) {
          // 英語形式 (DD MMM YYYY)
          const day = match[1];
          const monthAbbr = match[2].toUpperCase();
          const year = match[3];
          const month = this.convertMonthAbbrToNumber(monthAbbr);
          if (month) {
            return `${year}-${month.padStart(2, "0")}-${day}`;
          }
        } else if (match[1] && match[2] && match[3]) {
          // 日本語形式
          const year = match[1];
          const month = match[2].padStart(2, "0");
          const day = match[3].padStart(2, "0");
          return `${year}-${month}-${day}`;
        }
      }
    }

    return undefined;
  }

  /**
   * マイナンバーカードから氏名を抽出
   * @param {string} text - OCRテキスト
   * @return {string|undefined} 抽出された氏名
   */
  private extractNameFromMyNumberCard(text: string): string | undefined {
    const namePatterns = [
      /氏名\s*([^\n\r]+)/,
      /([一-龯ひ-ゖァ-ヶー]+\s+[一-龯ひ-ゖァ-ヶー]+)/,
    ];

    for (const pattern of namePatterns) {
      const match = text.match(pattern);
      if (match && match[1]) {
        return match[1].trim();
      }
    }

    return undefined;
  }

  /**
   * マイナンバーカードから生年月日を抽出
   * @param {string} text - OCRテキスト
   * @return {string|undefined} 抽出された生年月日
   */
  private extractBirthDateFromMyNumberCard(text: string): string | undefined {
    const datePatterns = [
      /生年月日\s*([0-9]{4})[年/\-.]([0-9]{1,2})[月/\-.]([0-9]{1,2})/,
      /([0-9]{4})[年/\-.]([0-9]{1,2})[月/\-.]([0-9]{1,2})/,
    ];

    for (const pattern of datePatterns) {
      const match = text.match(pattern);
      if (match && match[1] && match[2] && match[3]) {
        const year = match[1];
        const month = match[2].padStart(2, "0");
        const day = match[3].padStart(2, "0");
        return `${year}-${month}-${day}`;
      }
    }

    return undefined;
  }

  /**
   * 在留カードから氏名を抽出
   * @param {string} text - OCRテキスト
   * @return {string|undefined} 抽出された氏名
   */
  private extractNameFromResidenceCard(text: string): string | undefined {
    const namePatterns = [
      /氏名\s*([^\n\r]+)/,
      /Name\s*([A-Z\s]+)/i,
    ];

    for (const pattern of namePatterns) {
      const match = text.match(pattern);
      if (match && match[1]) {
        return match[1].trim();
      }
    }

    return undefined;
  }

  /**
   * 在留カードから生年月日を抽出
   * @param {string} text - OCRテキスト
   * @return {string|undefined} 抽出された生年月日
   */
  private extractBirthDateFromResidenceCard(text: string): string | undefined {
    const datePatterns = [
      /生年月日\s*([0-9]{4})[年/\-.]([0-9]{1,2})[月/\-.]([0-9]{1,2})/,
      /Date of Birth\s*([0-9]{2})\s*([A-Z]{3})\s*([0-9]{4})/i,
    ];

    for (const pattern of datePatterns) {
      const match = text.match(pattern);
      if (match) {
        if (match[1] && match[2] && match[3] && match[2].length === 3) {
          // 英語形式
          const day = match[1];
          const monthAbbr = match[2].toUpperCase();
          const year = match[3];
          const month = this.convertMonthAbbrToNumber(monthAbbr);
          if (month) {
            return `${year}-${month.padStart(2, "0")}-${day}`;
          }
        } else if (match[1] && match[2] && match[3]) {
          // 日本語形式
          const year = match[1];
          const month = match[2].padStart(2, "0");
          const day = match[3].padStart(2, "0");
          return `${year}-${month}-${day}`;
        }
      }
    }

    return undefined;
  }

  /**
   * 年齢を計算
   * @param {string} birthDateStr - 生年月日文字列
   * @return {number} 計算された年齢
   */
  private calculateAge(birthDateStr: string): number {
    const birthDate = new Date(birthDateStr);
    const today = new Date();
    let age = today.getFullYear() - birthDate.getFullYear();
    const monthDiff = today.getMonth() - birthDate.getMonth();

    if (monthDiff < 0 ||
        (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
      age--;
    }

    return age;
  }

  /**
   * 信頼度を計算
   * @param {object} extractedInfo - 抽出された情報
   * @param {string} ocrText - OCRテキスト
   * @return {number} 信頼度（0-1）
   */
  private calculateConfidence(
    extractedInfo: {
      extractedName?: string;
      extractedBirthDate?: string;
      extractedAge?: number;
    },
    ocrText: string
  ): number {
    let confidence = 0;

    // 氏名が抽出できた場合
    if (extractedInfo.extractedName) {
      confidence += 0.4;
      // 氏名が日本語の場合は信頼度アップ
      if (/[一-龯ひ-ゖァ-ヶー]/.test(extractedInfo.extractedName)) {
        confidence += 0.1;
      }
    }

    // 生年月日が抽出できた場合
    if (extractedInfo.extractedBirthDate) {
      confidence += 0.4;
      // 年齢が18歳以上の場合は信頼度アップ
      if (extractedInfo.extractedAge && extractedInfo.extractedAge >= 18) {
        confidence += 0.1;
      }
    }

    // OCRテキストの品質チェック
    if (ocrText.length > 50) {
      confidence += 0.1;
    }

    return Math.min(confidence, 1.0);
  }

  /**
   * 和暦を西暦に変換
   * @param {string} era - 元号
   * @param {number} eraYear - 元号年
   * @return {number|null} 西暦年
   */
  private convertEraToWestern(era: string, eraYear: number): number | null {
    const eraMap: {[key: string]: number} = {
      "令和": 2018,
      "平成": 1988,
      "昭和": 1925,
    };

    const baseYear = eraMap[era];
    if (baseYear) {
      return baseYear + eraYear;
    }

    return null;
  }

  /**
   * 月の略語を数字に変換
   * @param {string} monthAbbr - 月の略語
   * @return {string|null} 月の数字
   */
  private convertMonthAbbrToNumber(monthAbbr: string): string | null {
    const monthMap: {[key: string]: string} = {
      "JAN": "1", "FEB": "2", "MAR": "3", "APR": "4",
      "MAY": "5", "JUN": "6", "JUL": "7", "AUG": "8",
      "SEP": "9", "OCT": "10", "NOV": "11", "DEC": "12",
    };

    return monthMap[monthAbbr] || null;
  }
}
