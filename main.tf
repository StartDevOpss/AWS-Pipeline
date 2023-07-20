provider "aws" {
  region = "us-east-1"  # Altere para a região desejada
}

# Criar um bucket S3 para armazenar os artefatos do CodePipeline
resource "aws_s3_bucket" "pipeline_artifacts_bucket" {
  bucket = "example-pipeline-artifacts"
  acl    = "private"
}

# Criar um repositório do CodeCommit para o código do aplicativo
resource "aws_codecommit_repository" "app_repository" {
  repository_name = "example-app-repo"
  description     = "Example App Repository"
}

# Criar um projeto do CodeBuild para realizar o build do aplicativo
resource "aws_codebuild_project" "app_build_project" {
  name          = "example-app-build"
  description   = "Example App Build Project"
  service_role  = aws_iam_role.codebuild.arn
  artifacts {
    type = "NO_ARTIFACTS"
  }
  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:5.0"
    type         = "LINUX_CONTAINER"
  }
  source {
    type            = "CODEPIPELINE"
    buildspec       = file("${path.module}/buildspec.yml")
    git_clone_depth = 1
  }
}

# Criar uma aplicação do Elastic Beanstalk para a implantação
resource "aws_elastic_beanstalk_application" "app" {
  name = "example-app"
}

# Criar um ambiente de staging usando Elastic Beanstalk
resource "aws_elastic_beanstalk_environment" "staging_env" {
  name          = "example-staging-env"
  application   = aws_elastic_beanstalk_application.app.name
  solution_stack_name = "64bit Amazon Linux 2 v5.4.3 running Java 8"
  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MinSize"
    value     = "1"
  }
  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MaxSize"
    value     = "1"
  }
  setting {
    namespace = "aws:autoscaling:asg"
    name      = "DesiredCapacity"
    value     = "1"
  }
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "SingleInstance"
  }
}

# Criar um pipeline do CodePipeline para orquestrar as etapas
resource "aws_codepipeline" "example_pipeline" {
  name     = "example-pipeline"
  role_arn = aws_iam_role.pipeline.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "SourceAction"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["SourceArtifact"]

      configuration = {
        RepositoryName = aws_codecommit_repository.app_repository.name
        BranchName     = "main"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name            = "BuildAction"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["SourceArtifact"]
      version         = "1"

      configuration = {
        ProjectName = aws_codebuild_project.app_build_project.name
      }
    }
  }

  stage {
    name = "Staging"

    action {
      name            = "DeployToStaging"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ElasticBeanstalk"
      input_artifacts = ["SourceArtifact"]
      version         = "1"

      configuration = {
        ApplicationName = aws_elastic_beanstalk_application.app.name
        EnvironmentName = aws_elastic_beanstalk_environment.staging_env.name
      }
    }
  }
}

# Criar a política do IAM para o pipeline
resource "aws_iam_policy" "pipeline" {
  name        = "example-pipeline-policy"
  description = "Policy for the pipeline to access resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.pipeline_artifacts_bucket.arn,
          "${aws_s3_bucket.pipeline_artifacts_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codecommit:GitPull",
          "codecommit:GetBranch",
          "codecommit:GetCommit",
          "codecommit:UploadArchive",
          "codecommit:GetUploadArchiveStatus"
        ]
        Resource = aws_codecommit_repository.app_repository.arn
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:StartBuild",
          "codebuild:StopBuild"
        ]
        Resource = [
          aws_codebuild_project.app_build_project.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "elasticbeanstalk:*"
        ]
        Resource = [
          aws_elastic_beanstalk_application.app.arn,
          aws_elastic_beanstalk_environment.staging_env.arn
        ]
      }
    ]
  })
}

# Criar a função do IAM para o pipeline
resource "aws_iam_role" "pipeline" {
  name = "example-pipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      }
    ]
  })
}

# Anexar a política à função do IAM
resource "aws_iam_role_policy_attachment" "pipeline" {
  policy_arn = aws_iam_policy.pipeline.arn
  role       = aws_iam_role.pipeline.name
}
