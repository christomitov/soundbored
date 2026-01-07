defmodule Soundboard.VoiceListener.Transcriber do
  @moduledoc """
  Handles speech-to-text transcription using local whisper.cpp.
  """
  require Logger

  @whisper_bin_default "/usr/local/bin/whisper"
  @whisper_model_default "base.en"

  def transcribe(audio_data) when is_binary(audio_data) and byte_size(audio_data) > 0 do
    with {:ok, wav_path} <- convert_to_wav(audio_data),
         {:ok, text} <- run_whisper(wav_path) do
      {:ok, String.trim(text), nil}
    end
  end

  def transcribe(_), do: {:error, :empty_audio}

  defp convert_to_wav(opus_data) do
    tmp_input = "/tmp/voice_#{:erlang.unique_integer([:positive])}.opus"
    tmp_output = "/tmp/voice_#{:erlang.unique_integer([:positive])}.wav"

    try do
      File.write!(tmp_input, opus_data)

      case System.cmd("ffmpeg", [
        "-y", "-f", "opus", "-i", tmp_input,
        "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", "-f", "wav",
        tmp_output
      ], stderr_to_stdout: true) do
        {_, 0} -> {:ok, tmp_output}
        {output, code} ->
          Logger.warning("ffmpeg failed (#{code}): #{output}")
          File.rm(tmp_input)
          {:error, :ffmpeg_failed}
      end
    rescue
      e ->
        File.rm(tmp_input)
        {:error, {:conversion_error, e}}
    after
      File.rm(tmp_input)
    end
  end

  defp run_whisper(wav_path) do
    whisper_bin = Application.get_env(:soundboard, :whisper_bin, @whisper_bin_default)
    whisper_model = Application.get_env(:soundboard, :whisper_model, @whisper_model_default)
    models_dir = Application.get_env(:soundboard, :whisper_models_dir, "/usr/local/share/whisper")
    model_path = Path.join(models_dir, "ggml-#{whisper_model}.bin")

    if File.exists?(whisper_bin) do
      execute_whisper(whisper_bin, model_path, wav_path)
    else
      Logger.error("whisper.cpp not found at #{whisper_bin}")
      {:error, :whisper_not_found}
    end
  end

  defp execute_whisper(whisper_bin, model_path, wav_path) do
    args = ["-m", model_path, "-f", wav_path, "-nt", "-np", "--no-fallback", "-t", "4", "-l", "en"]

    case System.cmd(whisper_bin, args, stderr_to_stdout: true) do
      {output, 0} ->
        File.rm(wav_path)
        text = output
        |> String.split("\n")
        |> Enum.reject(&String.starts_with?(&1, "["))
        |> Enum.join(" ")
        |> String.trim()
        {:ok, text}

      {output, code} ->
        Logger.warning("whisper failed (#{code}): #{output}")
        File.rm(wav_path)
        {:error, {:whisper_failed, code}}
    end
  end
end
