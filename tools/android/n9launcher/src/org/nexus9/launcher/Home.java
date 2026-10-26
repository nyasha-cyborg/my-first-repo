package org.nexus9.launcher;

import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Color;
import android.graphics.drawable.Drawable;
import android.net.Uri;
import android.os.Bundle;
import android.provider.Settings;
import android.text.Editable;
import android.text.TextWatcher;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.AdapterView;
import android.widget.BaseAdapter;
import android.widget.EditText;
import android.widget.GridView;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

/** Minimal home screen: one grid of launchable apps over the wallpaper, with a filter box. Long-press = app info. */
public class Home extends Activity {

    private final List<App> all = new ArrayList<>();
    final List<App> shown = new ArrayList<>();
    private BaseAdapter adapter;
    private EditText filter;
    int iconPx, cellPx;

    private final BroadcastReceiver pkgChanged = new PkgReceiver(this);

    int dp(float v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics());
    }

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SHOW_WALLPAPER);
        iconPx = dp(56); cellPx = dp(96);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(32), dp(16), dp(16));

        filter = new EditText(this);
        filter.setHint("Search apps");
        filter.setSingleLine(true);
        filter.setTextColor(Color.WHITE);
        filter.setHintTextColor(0xAAFFFFFF);
        filter.setBackgroundColor(0x55000000);
        filter.setPadding(dp(12), dp(8), dp(12), dp(8));
        filter.addTextChangedListener(new Watcher(this));
        root.addView(filter, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        GridView grid = new GridView(this);
        grid.setColumnWidth(cellPx);
        grid.setNumColumns(GridView.AUTO_FIT);
        grid.setStretchMode(GridView.STRETCH_SPACING_UNIFORM);
        grid.setVerticalSpacing(dp(12));
        grid.setPadding(0, dp(16), 0, 0);
        grid.setClipToPadding(false);
        adapter = new Adapter(this);
        grid.setAdapter(adapter);
        grid.setOnItemClickListener(new Click(this));
        grid.setOnItemLongClickListener(new LongClick(this));
        root.addView(grid, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        setContentView(root);

        IntentFilter f = new IntentFilter();
        f.addAction(Intent.ACTION_PACKAGE_ADDED);
        f.addAction(Intent.ACTION_PACKAGE_REMOVED);
        f.addAction(Intent.ACTION_PACKAGE_CHANGED);
        f.addDataScheme("package");
        registerReceiver(pkgChanged, f);
        load();
    }

    @Override protected void onDestroy() { unregisterReceiver(pkgChanged); super.onDestroy(); }

    /** Home pressed while already home: clear the search. */
    @Override protected void onNewIntent(Intent i) { super.onNewIntent(i); filter.setText(""); }

    @Override public void onBackPressed() { filter.setText(""); }

    void load() {
        PackageManager pm = getPackageManager();
        Intent q = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
        List<ResolveInfo> ris = pm.queryIntentActivities(q, 0);
        all.clear();
        for (ResolveInfo ri : ris) {
            if (ri.activityInfo.packageName.equals(getPackageName())) continue;
            App a = new App();
            a.label = String.valueOf(ri.loadLabel(pm));
            a.cn = new ComponentName(ri.activityInfo.packageName, ri.activityInfo.name);
            a.icon = ri.loadIcon(pm);
            all.add(a);
        }
        Collections.sort(all, new ByLabel());
        applyFilter();
    }

    void applyFilter() {
        String s = filter.getText().toString().trim().toLowerCase(Locale.ROOT);
        shown.clear();
        for (App a : all) if (s.isEmpty() || a.label.toLowerCase(Locale.ROOT).contains(s)) shown.add(a);
        adapter.notifyDataSetChanged();
    }





}

final class App { String label; ComponentName cn; Drawable icon; }

final class ByLabel implements java.util.Comparator<App> {
    public int compare(App x, App y) { return x.label.compareToIgnoreCase(y.label); }
}

final class PkgReceiver extends BroadcastReceiver {
    final Home h; PkgReceiver(Home h) { this.h = h; }
    @Override public void onReceive(Context c, Intent i) { h.load(); }
}

final class Watcher implements TextWatcher {
    final Home h; Watcher(Home h) { this.h = h; }
    public void beforeTextChanged(CharSequence s, int a, int c, int d) {}
    public void onTextChanged(CharSequence s, int a, int c, int d) {}
    public void afterTextChanged(Editable s) { h.applyFilter(); }
}

final class Click implements AdapterView.OnItemClickListener {
    final Home h; Click(Home h) { this.h = h; }
    public void onItemClick(AdapterView<?> av, View v, int p, long id) {
        Intent i = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                .setComponent(h.shown.get(p).cn)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
        try { h.startActivity(i); } catch (Exception ignored) { }
    }
}

final class LongClick implements AdapterView.OnItemLongClickListener {
    final Home h; LongClick(Home h) { this.h = h; }
    public boolean onItemLongClick(AdapterView<?> av, View v, int p, long id) {
        h.startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", h.shown.get(p).cn.getPackageName(), null)));
        return true;
    }
}

final class Adapter extends BaseAdapter {
    final Home h; Adapter(Home h) { this.h = h; }
    public int getCount() { return h.shown.size(); }
    public Object getItem(int p) { return h.shown.get(p); }
    public long getItemId(int p) { return p; }
    public View getView(int p, View v, ViewGroup parent) {
        TextView t = (TextView) v;
        if (t == null) {
            t = new TextView(h);
            t.setGravity(Gravity.CENTER_HORIZONTAL);
            t.setTextColor(Color.WHITE);
            t.setShadowLayer(4, 0, 1, Color.BLACK);
            t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
            t.setMaxLines(2);
            t.setCompoundDrawablePadding(h.dp(4));
        }
        App a = h.shown.get(p);
        a.icon.setBounds(0, 0, h.iconPx, h.iconPx);
        t.setCompoundDrawables(null, a.icon, null, null);
        t.setText(a.label);
        return t;
    }
}
