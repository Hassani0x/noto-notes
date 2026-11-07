package app.hassani.noto;

import android.content.Context;
import android.graphics.*;
import android.graphics.drawable.GradientDrawable;
import android.view.View;

/** Paper swatches and the small folded-paper illustrations used by the notebook. */
final class Paper {
    static final int INK=0xff302c38, MUTED=0xff635c68, CANVAS=0xfffcfaf7, PLUM=0xff493b56;
    static final int[] PAINT={0xffffe6a9,0xfff8ceda,0xffcbe6fa,0xffdad3fa,0xffcfe8db};
    static final int[] EDGE={0xffa86c2a,0xff99516e,0xff427698,0xff7963ab,0xff437d68};
    static final String[] NAMES={"Butter","Blush","Sky","Lilac","Mint"};
    static GradientDrawable shape(int color,float radius){
        GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(radius);return d;
    }
    static class Illustration extends View {
        private final Paint p=new Paint(Paint.ANTI_ALIAS_FLAG);
        private final boolean folder;
        private final int index;
        Illustration(Context context,boolean folder,int index){super(context);this.folder=folder;this.index=index;setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);}
        private void rect(Canvas c,int color,float l,float t,float r,float b,float radius){
            p.setColor(color);c.drawRoundRect(l,t,r,b,radius,radius,p);
        }
        @Override protected void onDraw(Canvas c){
            float scale=Math.min(getWidth()/96f,getHeight()/76f);
            c.save();c.translate((getWidth()-96*scale)/2,(getHeight()-76*scale)/2);c.scale(scale,scale);
            if(folder){
                rect(c,Paper.EDGE[index],7,12,46,37,6);rect(c,Paper.EDGE[index],7,21,88,65,7);
                rect(c,0xfffffcf7,14,24,83,57,4);rect(c,Paper.PAINT[index],7,30,89,67,7);
                p.setColor(Paper.EDGE[index]);c.drawRoundRect(17,40,39,44,2,2,p);
            }else{
                c.rotate(-9,48,37);rect(c,0xffa99ac5,18,8,75,68,7);rect(c,0xfffffcf1,17,5,73,64,7);
                rect(c,0xffd6c8ec,17,5,26,64,4);rect(c,0xffe9a991,58,5,65,23,1);
                p.setColor(INK);c.drawCircle(41,35,2,p);c.drawCircle(56,35,2,p);
                p.setStyle(Paint.Style.STROKE);p.setStrokeWidth(2);c.drawArc(44,36,53,43,5,170,false,p);p.setStyle(Paint.Style.FILL);
            }
            c.restore();
        }
    }
}
