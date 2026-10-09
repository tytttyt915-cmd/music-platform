import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';

export class FeedQueryDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page = 1;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  pageSize = 20;

  /** trending=预测热度排序（默认，失败自动降级）；plays=累计播放量排序 */
  @IsOptional()
  @IsIn(['trending', 'plays'])
  sort: 'trending' | 'plays' = 'trending';
}

export class SearchQueryDto extends FeedQueryDto {
  @IsOptional()
  @IsString()
  q = '';
}
