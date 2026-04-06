using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace iPhotoImporter.Converters;

/// <summary>
/// Converter per agrupar dates per mes/any (ex: "Gener 2024").
/// </summary>
internal class MonthYearConverter : IValueConverter
{
    private static readonly string[] MonthNames =
        ["Gener", "Febrer", "Març", "Abril", "Maig", "Juny",
         "Juliol", "Agost", "Setembre", "Octubre", "Novembre", "Desembre"];

    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is DateTime dt)
            return $"{MonthNames[dt.Month - 1]} {dt.Year}";
        return "Sense data";
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

/// <summary>
/// Converter: null → false, no-null → true.
/// </summary>
internal class NullToBoolConverter : IValueConverter
{
    public static readonly NullToBoolConverter Instance = new();

    public object Convert(object? value, Type targetType, object parameter, CultureInfo culture)
        => value is not null;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

/// <summary>
/// Converter: bool → Visibility.
/// </summary>
internal class BoolToVisibilityConverter : IValueConverter
{
    public static readonly BoolToVisibilityConverter Instance = new();

    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        => value is true ? Visibility.Visible : Visibility.Collapsed;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

/// <summary>
/// Converter invers: bool → Visibility (true=Collapsed, false=Visible).
/// </summary>
internal class InverseBoolToVisibilityConverter : IValueConverter
{
    public static readonly InverseBoolToVisibilityConverter Instance = new();

    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        => value is true ? Visibility.Collapsed : Visibility.Visible;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

/// <summary>
/// Converter: 0 → Visible, altres → Collapsed.
/// </summary>
internal class ZeroToVisibilityConverter : IValueConverter
{
    public static readonly ZeroToVisibilityConverter Instance = new();

    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        => value is 0 ? Visibility.Visible : Visibility.Collapsed;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

/// <summary>
/// Converter: nombre > 0 → Visible, 0 → Collapsed.
/// </summary>
internal class PositiveToVisibilityConverter : IValueConverter
{
    public static readonly PositiveToVisibilityConverter Instance = new();

    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is int i) return i > 0 ? Visibility.Visible : Visibility.Collapsed;
        if (value is double d) return d > 0 ? Visibility.Visible : Visibility.Collapsed;
        return Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

/// <summary>
/// Converter: no-null → Visible, null → Collapsed.
/// </summary>
internal class NullToVisibilityConverter : IValueConverter
{
    public static readonly NullToVisibilityConverter Instance = new();

    public object Convert(object? value, Type targetType, object parameter, CultureInfo culture)
        => value is not null ? Visibility.Visible : Visibility.Collapsed;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

/// <summary>
/// Converter: double slider → mida de miniatura en píxels.
/// S=80, M=150, L=250, XL=400
/// </summary>
internal class ThumbnailSizeConverter : IValueConverter
{
    public static readonly ThumbnailSizeConverter Instance = new();

    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is double d)
            return (int)d;
        return 150;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

/// <summary>
/// Converter: mida en bytes → cadena llegible (KB, MB, GB).
/// </summary>
internal class FileSizeConverter : IValueConverter
{
    public static readonly FileSizeConverter Instance = new();

    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is long bytes)
        {
            return bytes switch
            {
                >= 1024L * 1024 * 1024 => $"{bytes / (1024.0 * 1024 * 1024):N1} GB",
                >= 1024L * 1024 => $"{bytes / (1024.0 * 1024):N1} MB",
                >= 1024L => $"{bytes / 1024.0:N0} KB",
                _ => $"{bytes} B"
            };
        }
        return "—";
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

/// <summary>
/// Multi-converter: pren dos booleans i retorna Visibility.
/// Es fa servir per mostrar/amagar elements basant-se en dues condicions.
/// </summary>
internal class MultiBoolToVisibilityConverter : IMultiValueConverter
{
    public static readonly MultiBoolToVisibilityConverter Instance = new();

    public object Convert(object[] values, Type targetType, object parameter, CultureInfo culture)
    {
        // Si qualsevol valor és true, mostra
        foreach (var v in values)
            if (v is true)
                return Visibility.Visible;
        return Visibility.Collapsed;
    }

    public object[] ConvertBack(object value, Type[] targetTypes, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}
