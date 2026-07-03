"""Utilitaires Spark partages par les jobs de traitement."""
from ingestion import config
from pyspark.sql import SparkSession

_HADOOP_AWS = "org.apache.hadoop:hadoop-aws:3.3.4"
_AWS_SDK = "com.amazonaws:aws-java-sdk-bundle:1.12.262"
_POSTGRES_JDBC = "org.postgresql:postgresql:42.7.3"


def creer_spark_local(nom: str) -> SparkSession:
    return (
        SparkSession.builder
        .appName(nom)
        .master("local[*]")
        .config("spark.sql.shuffle.partitions", "8")
        .config("spark.ui.showConsoleProgress", "false")
        .getOrCreate()
    )


def creer_spark_minio(nom: str) -> SparkSession:
    endpoint = config.MINIO_ENDPOINT
    if not endpoint.startswith("http"):
        endpoint = f"http://{endpoint}"
    return (
        SparkSession.builder
        .appName(nom)
        .master("local[*]")
        .config("spark.jars.packages", f"{_HADOOP_AWS},{_AWS_SDK},{_POSTGRES_JDBC}")
        .config("spark.hadoop.fs.s3a.endpoint", endpoint)
        .config("spark.hadoop.fs.s3a.access.key", config.MINIO_ACCESS_KEY)
        .config("spark.hadoop.fs.s3a.secret.key", config.MINIO_SECRET_KEY)
        .config("spark.hadoop.fs.s3a.path.style.access", "true")
        .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
        .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false")
        .config("spark.sql.shuffle.partitions", "8")
        .config("spark.ui.showConsoleProgress", "false")
        .getOrCreate()
    )


def jdbc_postgres() -> dict:
    hote = config._get("POSTGRES_HOST_LOCAL", "localhost")
    port = config._get("POSTGRES_PORT", "5432")
    base = config._get("POSTGRES_DB", "atmofrance")
    url = f"jdbc:postgresql://{hote}:{port}/{base}"
    proprietes = {
        "user": config._get("POSTGRES_USER", "atmo"),
        "password": config._get("POSTGRES_PASSWORD", "change_me"),
        "driver": "org.postgresql.Driver",
    }
    return {"url": url, "properties": proprietes}


def s3_path(bucket: str, prefixe: str = "") -> str:
    base = f"s3a://{bucket}"
    return f"{base}/{prefixe}" if prefixe else base
